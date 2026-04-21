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
        credentials: IMAPClient.Credentials,
        accountEmail: String,
        accountDisplayName: String?,
        folder: String = "INBOX",
        limit: Int = 50
    ) async throws -> SyncResult {
        let client = IMAPClient(credentials: credentials)
        let summaries = try await client.fetchRecentHeaders(folder: folder, limit: limit)

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
                    let (new, updated) = try self.upsertMessages(summaries, folder: folderObj, in: context)
                    folderObj.totalCount = Int32(summaries.count)
                    folderObj.unreadCount = Int32(summaries.filter { !$0.flags.contains(.seen) }.count)
                    account.lastSyncAt = Date()
                    try context.save()

                    cont.resume(returning: SyncResult(
                        folderPath: folder,
                        newMessages: new,
                        updatedMessages: updated,
                        totalInFolder: summaries.count
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
        credentials: IMAPClient.Credentials,
        in context: NSManagedObjectContext
    ) throws -> Account {
        let request: NSFetchRequest<Account> = Account.fetchRequest()
        request.predicate = NSPredicate(format: "emailAddress ==[c] %@", email)
        request.fetchLimit = 1

        if let existing = try context.fetch(request).first {
            existing.imapHost = credentials.host
            existing.imapPort = Int32(credentials.port)
            existing.imapUseSSL = credentials.useSSL
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
        account.imapUseSSL = credentials.useSSL
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
        folder.name = path
        folder.account = account
        return folder
    }

    private func upsertMessages(
        _ summaries: [MessageSummary],
        folder: Folder,
        in context: NSManagedObjectContext
    ) throws -> (new: Int, updated: Int) {
        guard !summaries.isEmpty else { return (0, 0) }

        let uids = summaries.map { Int64($0.uid) }
        let request: NSFetchRequest<Message> = Message.fetchRequest()
        request.predicate = NSPredicate(format: "folder == %@ AND uid IN %@", folder, uids)
        let existing = try context.fetch(request)
        let byUID = Dictionary(uniqueKeysWithValues: existing.map { (Int64($0.uid), $0) })

        var newCount = 0
        var updatedCount = 0

        for s in summaries {
            let uid = Int64(s.uid)
            if let msg = byUID[uid] {
                msg.flags = s.flags.rawValue
                updatedCount += 1
            } else {
                let msg = Message(context: context)
                msg.id = UUID()
                msg.uid = uid
                msg.messageID = s.messageID
                msg.subject = s.subject
                msg.from = s.from
                msg.to = s.to
                msg.cc = s.cc
                msg.date = s.date
                msg.flags = s.flags.rawValue
                msg.hasAttachments = s.hasAttachments
                msg.fetchedAt = Date()
                msg.folder = folder
                newCount += 1
            }
        }

        return (newCount, updatedCount)
    }
}
