import CoreData
import Foundation

public final class MailSyncCoordinator: @unchecked Sendable {
    private let container: NSPersistentContainer

    public init(container: NSPersistentContainer) {
        self.container = container
    }

    public struct SyncResult: Sendable {
        public let folderPath: String
        public let newMessages: Int
        public let updatedMessages: Int
        public let totalInFolder: Int
    }

    public func syncRecent(
        credentials: SwiftMailClient.Credentials,
        accountEmail: String,
        accountDisplayName: String?,
        folder: String = "INBOX",
        limit: Int = 50
    ) async throws -> SyncResult {
        let client = SwiftMailClient(credentials: credentials)
        let snapshots = try await client.fetchRecent(folder: folder, limit: limit)

        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        return try await withCheckedThrowingContinuation { cont in
            context.perform {
                do {
                    let account = try self.upsertAccount(
                        email: accountEmail,
                        displayName: accountDisplayName,
                        credentials: credentials,
                        in: context
                    )
                    let folderObj = try self.upsertFolder(
                        path: folder,
                        account: account,
                        in: context
                    )
                    let (new, updated) = try self.upsertMessages(snapshots, folder: folderObj, in: context)
                    folderObj.totalCount = Int32(snapshots.count)
                    account.lastSyncAt = Date()
                    try context.save()

                    cont.resume(returning: SyncResult(
                        folderPath: folder,
                        newMessages: new,
                        updatedMessages: updated,
                        totalInFolder: snapshots.count
                    ))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func upsertAccount(
        email: String,
        displayName: String?,
        credentials: SwiftMailClient.Credentials,
        in context: NSManagedObjectContext
    ) throws -> Account {
        let request: NSFetchRequest<Account> = Account.fetchRequest()
        request.predicate = NSPredicate(format: "emailAddress ==[c] %@", email)
        request.fetchLimit = 1

        if let existing = try context.fetch(request).first {
            existing.imapHost = credentials.host
            existing.imapPort = Int32(credentials.port)
            existing.imapUseSSL = true
            existing.username = credentials.username
            if let displayName = displayName {
                existing.displayName = displayName
            }
            return existing
        }

        let account = Account(context: context)
        account.id = UUID()
        account.emailAddress = email
        account.displayName = displayName ?? email
        account.imapHost = credentials.host
        account.imapPort = Int32(credentials.port)
        account.imapUseSSL = true
        account.username = credentials.username
        account.createdAt = Date()
        return account
    }

    private func upsertFolder(
        path: String,
        account: Account,
        in context: NSManagedObjectContext
    ) throws -> Folder {
        let request: NSFetchRequest<Folder> = Folder.fetchRequest()
        request.predicate = NSPredicate(format: "account == %@ AND path ==[c] %@", account, path)
        request.fetchLimit = 1

        if let existing = try context.fetch(request).first {
            return existing
        }

        let folder = Folder(context: context)
        folder.id = UUID()
        folder.path = path
        folder.name = path.split(separator: "/").last.map(String.init) ?? path
        folder.role = path.uppercased() == "INBOX" ? MailFolderRole.inbox.rawValue : MailFolderRole.other.rawValue
        folder.account = account
        return folder
    }

    public func syncFolders(
        credentials: SwiftMailClient.Credentials,
        accountEmail: String,
        accountDisplayName: String?
    ) async throws -> [String] {
        let client = SwiftMailClient(credentials: credentials)
        let infos = try await client.listFolders()

        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        return try await withCheckedThrowingContinuation { cont in
            context.perform {
                do {
                    let account = try self.upsertAccount(
                        email: accountEmail,
                        displayName: accountDisplayName,
                        credentials: credentials,
                        in: context
                    )
                    var paths: [String] = []
                    for info in infos {
                        let folder = try self.upsertFolder(path: info.path, account: account, in: context)
                        folder.role = info.role.rawValue
                        folder.name = info.displayName
                        paths.append(info.path)
                    }
                    try context.save()
                    cont.resume(returning: paths)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    public func createFolder(
        credentials: SwiftMailClient.Credentials,
        accountEmail: String,
        path: String
    ) async throws {
        let client = SwiftMailClient(credentials: credentials)
        try await client.createFolder(path: path)
        // Refresh folder list so the new one shows up locally.
        _ = try await syncFolders(
            credentials: credentials,
            accountEmail: accountEmail,
            accountDisplayName: nil
        )
    }

    private func upsertMessages(
        _ snapshots: [SwiftMailSnapshot],
        folder: Folder,
        in context: NSManagedObjectContext
    ) throws -> (new: Int, updated: Int) {
        guard !snapshots.isEmpty else { return (0, 0) }

        let uids = snapshots.map { Int64($0.uid) }
        let request: NSFetchRequest<Message> = Message.fetchRequest()
        request.predicate = NSPredicate(format: "folder == %@ AND uid IN %@", folder, uids)
        let existing = try context.fetch(request)
        let byUID = Dictionary(uniqueKeysWithValues: existing.map { (Int64($0.uid), $0) })

        var newCount = 0
        var updatedCount = 0

        for s in snapshots {
            let uid = Int64(s.uid)
            if let msg = byUID[uid] {
                // Update fields that may have changed
                msg.subject = s.subject
                msg.from = s.from
                msg.date = s.date
                msg.preview = s.preview
                updatedCount += 1
            } else {
                let msg = Message(context: context)
                msg.id = UUID()
                msg.uid = uid
                msg.subject = s.subject
                msg.from = s.from
                msg.date = s.date
                msg.preview = s.preview
                msg.fetchedAt = Date()
                msg.folder = folder
                newCount += 1
            }
        }

        return (newCount, updatedCount)
    }
}
