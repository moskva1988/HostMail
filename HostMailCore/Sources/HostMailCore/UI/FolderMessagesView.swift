import CoreData
import SwiftUI

public struct FolderMessagesView: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var folder: Folder
    @Binding var selectedMessage: NSManagedObjectID?

    @FetchRequest private var messages: FetchedResults<Message>

    @State private var syncing = false
    @State private var syncError: String?
    @State private var lastSyncSummary: String = ""

    public init(folder: Folder, selectedMessage: Binding<NSManagedObjectID?>) {
        self._folder = ObservedObject(wrappedValue: folder)
        self._selectedMessage = selectedMessage
        self._messages = FetchRequest(
            sortDescriptors: [
                NSSortDescriptor(keyPath: \Message.date, ascending: false),
                NSSortDescriptor(keyPath: \Message.fetchedAt, ascending: false)
            ],
            predicate: NSPredicate(format: "folder == %@", folder)
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            statusHeader
            list
        }
        .navigationTitle(folder.name ?? "Folder")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await runSync() }
                } label: {
                    if syncing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(syncing)
            }
        }
        .task { await runSyncIfStale() }
    }

    private var statusHeader: some View {
        VStack(spacing: 4) {
            if let banner = currentBanner {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: banner.icon).foregroundStyle(banner.tint)
                    Text(banner.text).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            HStack {
                if let date = folder.account?.lastSyncAt {
                    Text("Synced \(date.formatted(.relative(presentation: .named)))")
                } else {
                    Text("Never synced")
                }
                Spacer()
                Text("\(messages.count) cached")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var list: some View {
        if messages.isEmpty {
            VStack {
                Spacer()
                Text("No messages — tap Refresh to sync.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List(selection: $selectedMessage) {
                ForEach(messages, id: \.objectID) { msg in
                    MessageRow(message: msg)
                        .tag(msg.objectID as NSManagedObjectID?)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private struct Banner {
        let text: String
        let icon: String
        let tint: Color
    }

    private var currentBanner: Banner? {
        if syncing {
            return Banner(text: "Syncing…", icon: "arrow.clockwise", tint: HostTheme.accent)
        }
        if let error = syncError {
            return Banner(text: error, icon: "exclamationmark.triangle.fill", tint: HostTheme.errorRed)
        }
        if !lastSyncSummary.isEmpty {
            return Banner(text: lastSyncSummary, icon: "checkmark.circle.fill", tint: HostTheme.successGreen)
        }
        return nil
    }

    private func runSyncIfStale() async {
        // Auto-sync if there are no cached messages and we haven't tried this
        // session — gives the user something on first folder open without a tap.
        if messages.isEmpty && !syncing {
            await runSync()
        }
    }

    private func runSync() async {
        guard let account = folder.account,
              let email = account.emailAddress,
              let host = account.imapHost,
              let path = folder.path else { return }
        guard let password = try? KeychainStore().loadPassword(for: email) else {
            syncError = "Password not in Keychain. Open Settings to re-add account."
            return
        }
        let creds = SwiftMailClient.Credentials(
            host: host,
            port: Int(account.imapPort > 0 ? account.imapPort : 993),
            username: account.username ?? email,
            password: password
        )
        syncing = true
        defer { syncing = false }
        do {
            let coord = MailSyncCoordinator(container: PersistenceController.shared.container)
            let res = try await coord.syncRecent(
                credentials: creds,
                accountEmail: email,
                accountDisplayName: account.displayName,
                folder: path,
                limit: 50
            )
            lastSyncSummary = "+\(res.newMessages) new, ~\(res.updatedMessages) updated, -\(res.deletedMessages) deleted"
            syncError = nil
        } catch {
            syncError = "Sync failed: \(error.localizedDescription)"
        }
    }
}

struct MessageRow: View {
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
