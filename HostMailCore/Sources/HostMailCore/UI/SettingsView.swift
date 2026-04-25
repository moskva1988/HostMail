import CoreData
import SwiftUI

public struct SettingsView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.createdAt, ascending: true)]
    ) private var accounts: FetchedResults<Account>

    @State private var aiStatus: String = ""
    @State private var aiTesting = false
    @State private var aiResult: String = ""
    @State private var showSignOutConfirm: Account?

    public init() {}

    public var body: some View {
        Form {
            Section("Accounts") {
                if accounts.isEmpty {
                    Text("No accounts configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(accounts, id: \.objectID) { account in
                        accountRow(account)
                    }
                }
            }

            Section("AI Provider") {
                Label(aiStatus, systemImage: "brain.head.profile")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    runAITest()
                } label: {
                    HStack(spacing: 6) {
                        if aiTesting { ProgressView().controlSize(.small) }
                        Text("Test Apple Intelligence (summarize)")
                    }
                }
                .disabled(aiTesting)

                if !aiResult.isEmpty {
                    Text(aiResult)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("BYOK API keys for Claude / OpenAI / Yandex / GigaChat — coming next.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("HostMail", value: "v\(HostMailCore.version)")
                LabeledContent("Engine", value: "SwiftMail (pure Swift IMAP/SMTP)")
                LabeledContent("Sync", value: PersistenceController.shared.cloudKitEnabled ? "Core Data + CloudKit" : "Local-only")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .task { refreshAIStatus() }
        .confirmationDialog("Sign out of \(showSignOutConfirm?.emailAddress ?? "")?", isPresented: signOutBinding, titleVisibility: .visible, presenting: showSignOutConfirm) { account in
            Button("Sign Out", role: .destructive) { signOut(account) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Removes the account, all cached messages, and the Keychain password from this device. CloudKit data will be deleted on next sync if iCloud is enabled.")
        }
    }

    private var signOutBinding: Binding<Bool> {
        Binding(get: { showSignOutConfirm != nil },
                set: { if !$0 { showSignOutConfirm = nil } })
    }

    @ViewBuilder
    private func accountRow(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName ?? account.emailAddress ?? "Account")
                        .font(.subheadline.weight(.semibold))
                    if let email = account.emailAddress {
                        Text(email).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(role: .destructive) {
                    showSignOutConfirm = account
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(HostTheme.errorRed)
            }
            HStack(spacing: 12) {
                Text("IMAP:")
                    .foregroundStyle(.secondary)
                Text("\(account.imapHost ?? "—"):\(account.imapPort)")
                    .monospaced()
            }
            .font(.caption)
            if let date = account.lastSyncAt {
                Text("Last synced \(date.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func refreshAIStatus() {
        let provider = ApplePrivateProvider()
        aiStatus = provider.isConfigured
            ? "Apple Intelligence: Ready"
            : "Apple Intelligence: Not available on this device"
    }

    private func runAITest() {
        aiTesting = true
        aiResult = ""
        Task {
            defer { aiTesting = false }
            do {
                let r = try await ApplePrivateProvider().summarize(
                    "HostMail is a native iOS and macOS email client with built-in AI assistance."
                )
                aiResult = r
            } catch {
                aiResult = "Error: \(error.localizedDescription)"
            }
        }
    }

    private func signOut(_ account: Account) {
        if let email = account.emailAddress {
            try? KeychainStore().deletePassword(for: email)
        }
        let bg = PersistenceController.shared.container.newBackgroundContext()
        let id = account.objectID
        bg.perform {
            if let obj = try? bg.existingObject(with: id) {
                bg.delete(obj)
                try? bg.save()
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
