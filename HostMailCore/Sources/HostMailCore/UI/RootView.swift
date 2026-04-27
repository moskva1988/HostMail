import CoreData
import SwiftUI

public struct RootView: View {
    @State private var showSplash = true

    public init() {}

    public var body: some View {
        ZStack {
            ShellView()
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

// MARK: - 3-column shell (Sidebar / Messages / Detail)

private struct ShellView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.createdAt, ascending: true)]
    ) private var accounts: FetchedResults<Account>

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Folder.role, ascending: true),
            NSSortDescriptor(keyPath: \Folder.name, ascending: true)
        ]
    ) private var folders: FetchedResults<Folder>

    @State private var sidebarSelection: SidebarItem?
    @State private var selectedMessage: NSManagedObjectID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showSyncSheet = false
    @State private var showNewFolderSheet = false  // kept for future folder workflow

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $sidebarSelection, showNewFolderSheet: $showNewFolderSheet)
                .navigationTitle("HostMail")
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
                .toolbar {
                    ToolbarItem {
                        Button {
                            showSyncSheet = true
                        } label: {
                            Image(systemName: accounts.isEmpty ? "plus.circle.fill" : "arrow.clockwise")
                        }
                    }
                }
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        } detail: {
            detailColumn
        }
        .sheet(isPresented: $showSyncSheet) {
            SyncSheet(existingAccount: accounts.first)
        }
        .sheet(isPresented: $showNewFolderSheet) {
            NewFolderSheet(account: accounts.first)
        }
        .onAppear { applyDefaultSelection() }
        .onChange(of: folders.count) { _, _ in
            applyDefaultSelection()
        }
        .task {
            await autoBootstrap()
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch sidebarSelection {
        case .folder(let id):
            if let folder = try? context.existingObject(with: id) as? Folder {
                FolderMessagesView(folder: folder, selectedMessage: $selectedMessage)
            } else {
                Text("Folder not found").foregroundStyle(.secondary)
            }
        case .settings:
            SettingsView()
        case .addAccount, .none:
            VStack(spacing: 12) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(HostTheme.accent)
                Text("Welcome to HostMail")
                    .font(.title3.weight(.semibold))
                if accounts.isEmpty {
                    Text("Add an IMAP account to start.")
                        .foregroundStyle(.secondary)
                    Button("Add Account") { showSyncSheet = true }
                        .buttonStyle(.borderedProminent)
                        .tint(HostTheme.accent)
                } else {
                    Text("Pick a folder from the sidebar.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let id = selectedMessage,
           let msg = try? context.existingObject(with: id) as? Message {
            MessageDetailView(message: msg)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Select a message")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func applyDefaultSelection() {
        if sidebarSelection == nil, let inbox = folders.first(where: { $0.role == "inbox" }) ?? folders.first {
            sidebarSelection = .folder(inbox.objectID)
        }
    }

    // Bootstraps the first launch with a saved Keychain account: refresh the
    // folder list (to populate the sidebar) and let FolderMessagesView do the
    // initial INBOX sync once the user lands there.
    private func autoBootstrap() async {
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
        let coord = MailSyncCoordinator(container: PersistenceController.shared.container)
        _ = try? await coord.syncFolders(
            credentials: creds,
            accountEmail: email,
            accountDisplayName: account.displayName
        )
    }
}

// MARK: - Sync sheet (Add account / re-sync)

private struct SyncSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existingAccount: Account?

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
            Text(existingAccount != nil ? "Sync Account" : "Add Account")
                .font(.title2.bold())
            Text("Password is held in memory; if 'Save password' is on it goes to the device Keychain (never iCloud Core Data).")
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
        let displayNameLocal = displayName
        Task {
            defer { running = false }
            do {
                _ = try await coordinator.syncFolders(
                    credentials: creds,
                    accountEmail: userEmail,
                    accountDisplayName: displayNameLocal.isEmpty ? nil : displayNameLocal
                )
                let res = try await coordinator.syncRecent(
                    credentials: creds,
                    accountEmail: userEmail,
                    accountDisplayName: displayNameLocal.isEmpty ? nil : displayNameLocal,
                    folder: "INBOX",
                    limit: 50
                )
                if saveFlag {
                    try? KeychainStore().savePassword(pwd, for: userEmail)
                } else {
                    try? KeychainStore().deletePassword(for: userEmail)
                }
                output = "INBOX: +\(res.newMessages) new, ~\(res.updatedMessages) updated, -\(res.deletedMessages) deleted"
                dismiss()
            } catch {
                output = "Error: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - New Folder sheet (IMAP CREATE)

private struct NewFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let account: Account?

    @State private var path: String = ""
    @State private var running = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Folder").font(.title2.bold())
            Text("Use a slash to nest, e.g. INBOX/Receipts.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Folder path", text: $path)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(HostTheme.errorRed)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(action: create) {
                    HStack(spacing: 6) {
                        if running { ProgressView().controlSize(.small) }
                        Text("Create")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(HostTheme.accent)
                .disabled(running || path.isEmpty || account == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 380)
    }

    private func create() {
        guard let account = account,
              let email = account.emailAddress,
              let host = account.imapHost else {
            error = "No account."
            return
        }
        guard let password = try? KeychainStore().loadPassword(for: email) else {
            error = "Password not in Keychain."
            return
        }
        let creds = SwiftMailClient.Credentials(
            host: host,
            port: Int(account.imapPort > 0 ? account.imapPort : 993),
            username: account.username ?? email,
            password: password
        )
        let folderPath = path
        running = true
        Task {
            defer { running = false }
            do {
                let coord = MailSyncCoordinator(container: PersistenceController.shared.container)
                try await coord.createFolder(
                    credentials: creds,
                    accountEmail: email,
                    path: folderPath
                )
                dismiss()
            } catch {
                self.error = "Failed: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    RootView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
