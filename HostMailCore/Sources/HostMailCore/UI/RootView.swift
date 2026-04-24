import CoreData
import SwiftUI

public struct RootView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            InboxView()
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

    var body: some View {
        Group {
            if accounts.isEmpty {
                emptyState
            } else {
                inboxList
            }
        }
        .navigationTitle("HostMail")
        .toolbar { toolbar }
        .sheet(isPresented: $showSyncSheet) {
            SyncSheet(
                existingAccount: accounts.first,
                onResult: { lastSyncSummary = $0 }
            )
        }
        .sheet(isPresented: $showAITest) {
            AppleIntelligenceTestSheet()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
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
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inboxList: some View {
        List {
            if !lastSyncSummary.isEmpty {
                Section {
                    Text(lastSyncSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section(header: header) {
                if messages.isEmpty {
                    Text("Inbox is empty — tap Sync to fetch messages.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(messages, id: \.objectID) { msg in
                        MessageRow(message: msg)
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private var header: some View {
        HStack {
            if let account = accounts.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName ?? account.emailAddress ?? "Account")
                        .font(.subheadline.weight(.semibold))
                    if let date = account.lastSyncAt {
                        Text("Last synced \(date.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never synced")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text("\(messages.count) cached")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
}

// MARK: - Message row

private struct MessageRow: View {
    let message: Message

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
    @State private var running = false
    @State private var output: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existingAccount != nil ? "Sync Inbox" : "Add Account")
                .font(.title2.bold())
            Text("Password is held in memory only for this sync. Persistent Keychain storage arrives in the Add-Account screen.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                TextField("Display name (optional)", text: $displayName)
                TextField("Email / Username", text: $email)
                    .textContentType(.username)
                    .disableAutocorrection(true)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                #endif
                SecureField("Password / App Password", text: $password)
                TextField("IMAP Host", text: $host)
                    .disableAutocorrection(true)
                TextField("Port", text: $port)
                    .frame(maxWidth: 100)
            }
            .textFieldStyle(.roundedBorder)

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
        Task {
            defer { running = false }
            do {
                let res = try await coordinator.syncRecent(
                    credentials: creds,
                    accountEmail: email,
                    accountDisplayName: displayName.isEmpty ? nil : displayName,
                    folder: "INBOX",
                    limit: 50
                )
                let summary = "\(res.folderPath): +\(res.newMessages) new, ~\(res.updatedMessages) updated, \(res.totalInFolder) total fetched"
                output = summary
                onResult(summary)
                dismiss()
            } catch {
                output = "Error: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Apple Intelligence test sheet (dev tool, kept until Settings UI)

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
