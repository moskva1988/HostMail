import CoreData
import SwiftUI

public struct RootView: View {
    @State private var showSplash = true

    public init() {}

    public var body: some View {
        ZStack {
            NavigationStack {
                InboxView()
            }
            .tint(HostTheme.accent)
            .opacity(showSplash ? 0 : 1)

            if showSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeInOut(duration: 0.4)) {
                showSplash = false
            }
        }
    }
}

// MARK: - Inbox

private struct InboxView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Message.date, ascending: false),
            NSSortDescriptor(keyPath: \Message.fetchedAt, ascending: false)
        ]
    ) private var messages: FetchedResults<Message>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.createdAt, ascending: true)]
    ) private var accounts: FetchedResults<Account>

    @State private var showSyncSheet = false
    @State private var showAITest = false
    @State private var lastSyncSummary: String = ""
    @State private var syncing = false
    @State private var syncError: String?

    var body: some View {
        Group {
            if accounts.isEmpty {
                emptyState
            } else {
                inboxList
            }
        }
        .navigationTitle(navTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar { toolbar }
        .sheet(isPresented: $showSyncSheet) {
            SyncSheet(
                existingAccount: accounts.first,
                onResult: { lastSyncSummary = $0; syncError = nil }
            )
        }
        .sheet(isPresented: $showAITest) {
            AppleIntelligenceTestSheet()
        }
        .task { await autoSyncIfPossible() }
    }

    private var navTitle: String {
        if accounts.isEmpty { return "HostMail" }
        return accounts.first?.displayName ?? accounts.first?.emailAddress ?? "HostMail"
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(HostTheme.accent)
            Text("No account yet")
                .font(.title3.weight(.semibold))
            Text("Add an IMAP account to start syncing your inbox.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showSyncSheet = true
            } label: {
                Text("Add Account").frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .tint(HostTheme.accent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inboxList: some View {
        List {
            if let summary = currentBanner {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: summary.icon)
                            .foregroundStyle(summary.tint)
                        Text(summary.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                if messages.isEmpty {
                    Text("Inbox is empty — tap Sync to fetch messages.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(messages, id: \.objectID) { msg in
                        NavigationLink {
                            MessageDetailView(message: msg)
                        } label: {
                            MessageRow(message: msg)
                        }
                    }
                }
            } header: {
                inboxHeader
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private var inboxHeader: some View {
        HStack {
            if let date = accounts.first?.lastSyncAt {
                Text("Synced \(date.formatted(.relative(presentation: .named)))")
            } else {
                Text("Never synced")
            }
            Spacer()
            Text("\(messages.count) cached")
        }
        .font(.caption2)
        .textCase(nil)
    }

    private struct Banner {
        let text: String
        let icon: String
        let tint: Color
    }

    private var currentBanner: Banner? {
        if syncing {
            return Banner(text: "Syncing inbox…", icon: "arrow.clockwise", tint: HostTheme.accent)
        }
        if let error = syncError {
            return Banner(text: error, icon: "exclamationmark.triangle", tint: HostTheme.errorRed)
        }
        if !lastSyncSummary.isEmpty {
            return Banner(text: lastSyncSummary, icon: "checkmark.circle", tint: HostTheme.successGreen)
        }
        return nil
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showSyncSheet = true
            } label: {
                if syncing {
                    ProgressView()
                } else {
                    Image(systemName: accounts.isEmpty ? "plus.circle" : "arrow.clockwise")
                }
            }
            .disabled(syncing)
        }
        ToolbarItem(placement: .secondaryAction) {
            Button {
                showAITest = true
            } label: {
                Label("Test Apple Intelligence", systemImage: "brain.head.profile")
            }
        }
    }

    // Silent background sync if we already know about an account AND the password
    // is in Keychain — runs once when InboxView appears.
    private func autoSyncIfPossible() async {
        guard let account = accounts.first,
              let email = account.emailAddress,
              let host = account.imapHost else { return }
        guard let password = try? KeychainStore().loadPassword(for: email) else { return }

        let creds = SwiftMailClient.Credentials(
            host: host,
            port: Int(account.imapPort > 0 ? account.imapPort : 993),
            username: account.username ?? email,
            password: password
        )
        await runSync(credentials: creds, accountEmail: email, displayName: account.displayName)
    }

    fileprivate func runSync(credentials: SwiftMailClient.Credentials, accountEmail: String, displayName: String?) async {
        syncing = true
        defer { syncing = false }
        do {
            let coordinator = MailSyncCoordinator(container: PersistenceController.shared.container)
            let res = try await coordinator.syncRecent(
                credentials: credentials,
                accountEmail: accountEmail,
                accountDisplayName: displayName,
                folder: "INBOX",
                limit: 50
            )
            lastSyncSummary = "INBOX: +\(res.newMessages) new, ~\(res.updatedMessages) updated, \(res.totalInFolder) total"
            syncError = nil
        } catch {
            syncError = "Sync failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Message row

private struct MessageRow: View {
    @ObservedObject var message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.from ?? "(unknown sender)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if let date = message.date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(message.subject ?? "(no subject)")
                .font(.subheadline)
                .lineLimit(2)
            if let preview = message.preview, !preview.isEmpty {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Sync sheet

private struct SyncSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingAccount: Account?
    let onResult: (String) -> Void

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var host: String = "imap.gmail.com"
    @State private var port: String = "993"
    @State private var displayName: String = ""
    @State private var savePassword: Bool = true
    @State private var running = false
    @State private var output: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existingAccount != nil ? "Sync Inbox" : "Add Account")
                .font(.title2.bold())
            Text("If \"Save password\" is on, the password is stored in the device Keychain — never in iCloud Core Data.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                TextField("Display name (optional)", text: $displayName)
                TextField("Email / Username", text: $email)
                    .disableAutocorrection(true)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                #endif
                SecureField("Password / App Password", text: $password)
                    .textContentType(.password)
                TextField("IMAP Host", text: $host)
                    .disableAutocorrection(true)
                TextField("Port", text: $port)
                    .frame(maxWidth: 100)
            }
            .textFieldStyle(.roundedBorder)

            Toggle("Save password to Keychain", isOn: $savePassword)
                .tint(HostTheme.accent)

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(action: run) {
                    HStack(spacing: 6) {
                        if running { ProgressView().controlSize(.small) }
                        Text(existingAccount != nil ? "Sync 50" : "Add & Sync 50")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(HostTheme.accent)
                .disabled(running || email.isEmpty || password.isEmpty || host.isEmpty)
            }

            if !output.isEmpty {
                ScrollView {
                    Text(output)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 140)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .onAppear {
            if let a = existingAccount {
                email = a.emailAddress ?? ""
                host = a.imapHost ?? "imap.gmail.com"
                port = String(a.imapPort > 0 ? a.imapPort : 993)
                displayName = a.displayName ?? ""
                if let saved = try? KeychainStore().loadPassword(for: email) {
                    password = saved
                }
            }
        }
    }

    private func run() {
        running = true
        output = ""
        let creds = SwiftMailClient.Credentials(
            host: host,
            port: Int(port) ?? 993,
            username: email,
            password: password
        )
        let coordinator = MailSyncCoordinator(container: PersistenceController.shared.container)
        let pwd = password
        let saveFlag = savePassword
        let userEmail = email
        Task {
            defer { running = false }
            do {
                let res = try await coordinator.syncRecent(
                    credentials: creds,
                    accountEmail: userEmail,
                    accountDisplayName: displayName.isEmpty ? nil : displayName,
                    folder: "INBOX",
                    limit: 50
                )
                if saveFlag {
                    try? KeychainStore().savePassword(pwd, for: userEmail)
                } else {
                    try? KeychainStore().deletePassword(for: userEmail)
                }
                let summary = "INBOX: +\(res.newMessages) new, ~\(res.updatedMessages) updated, \(res.totalInFolder) total"
                output = summary
                onResult(summary)
                dismiss()
            } catch {
                output = "Error: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Apple Intelligence test sheet (dev tool)

private struct AppleIntelligenceTestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var status: String = ""
    @State private var result: String = ""
    @State private var running = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Intelligence")
                .font(.title2.bold())
            Text(status).font(.footnote).foregroundStyle(.secondary)
            Button {
                run()
            } label: {
                HStack(spacing: 6) {
                    if running { ProgressView().controlSize(.small) }
                    Text("Run Summary Test")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(HostTheme.accent)
            .disabled(running)
            if !result.isEmpty {
                ScrollView {
                    Text(result)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 220)
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
        .onAppear {
            let provider = ApplePrivateProvider()
            status = provider.isConfigured
                ? "Apple Intelligence: Ready"
                : "Apple Intelligence: Not available on this device"
        }
    }

    private func run() {
        running = true
        result = ""
        Task {
            defer { running = false }
            do {
                let r = try await ApplePrivateProvider().summarize(
                    "HostMail is a native iOS and macOS email client with built-in AI assistance. It uses Apple Intelligence by default and supports BYOK for Claude, OpenAI, Yandex Alice, and GigaChat."
                )
                result = r
            } catch {
                result = "Error: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    RootView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
