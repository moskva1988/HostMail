import CoreData
import SwiftUI

public enum SidebarItem: Hashable, Sendable {
    case folder(NSManagedObjectID)
    case settings
    case addAccount
}

public struct SidebarView: View {
    @Environment(\.managedObjectContext) private var context
    @Binding var selection: SidebarItem?
    @Binding var showNewFolderSheet: Bool

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.createdAt, ascending: true)]
    ) private var accounts: FetchedResults<Account>

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Folder.role, ascending: true),
            NSSortDescriptor(keyPath: \Folder.name, ascending: true)
        ]
    ) private var folders: FetchedResults<Folder>

    public init(selection: Binding<SidebarItem?>, showNewFolderSheet: Binding<Bool>) {
        self._selection = selection
        self._showNewFolderSheet = showNewFolderSheet
    }

    public var body: some View {
        List(selection: $selection) {
            if let account = accounts.first {
                Section {
                    accountHeader(account)
                }
            }

            if !folders.isEmpty {
                Section("Mail") {
                    ForEach(orderedFolders, id: \.objectID) { folder in
                        folderRow(folder)
                            .tag(SidebarItem.folder(folder.objectID))
                    }
                }
            }

            Section("App") {
                Label("Settings", systemImage: "gearshape")
                    .tag(SidebarItem.settings)
                if accounts.isEmpty {
                    Label("Add Account…", systemImage: "person.crop.circle.badge.plus")
                        .tag(SidebarItem.addAccount)
                }
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #endif
    }

    @ViewBuilder
    private func accountHeader(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(account.displayName ?? account.emailAddress ?? "Account")
                .font(.subheadline.weight(.semibold))
            if let email = account.emailAddress {
                Text(email)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var orderedFolders: [Folder] {
        // Sort: by role priority first (inbox, sent, drafts, archive, trash, junk, other),
        // then alphabetically by display name within each role group.
        folders.sorted { a, b in
            let pa = priority(for: a.role)
            let pb = priority(for: b.role)
            if pa != pb { return pa < pb }
            return (a.name ?? "").localizedStandardCompare(b.name ?? "") == .orderedAscending
        }
    }

    private func priority(for role: String?) -> Int {
        switch role {
        case "inbox":   0
        case "sent":    1
        case "drafts":  2
        case "archive": 3
        case "trash":   4
        case "junk":    5
        default:        6
        }
    }

    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
        let icon = iconName(for: folder.role)
        let displayName = folder.name ?? folder.path ?? "(folder)"
        HStack {
            Label(displayName, systemImage: icon)
            Spacer()
            if folder.totalCount > 0 {
                Text("\(folder.totalCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func iconName(for role: String?) -> String {
        switch role {
        case "inbox":   "tray"
        case "sent":    "paperplane"
        case "drafts":  "square.and.pencil"
        case "trash":   "trash"
        case "junk":    "exclamationmark.shield"
        case "archive": "archivebox"
        default:        "folder"
        }
    }
}
