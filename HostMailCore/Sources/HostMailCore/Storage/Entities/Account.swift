import CoreData
import Foundation

@objc(Account)
public final class Account: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Account> {
        NSFetchRequest<Account>(entityName: "Account")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var displayName: String?
    @NSManaged public var emailAddress: String?
    @NSManaged public var imapHost: String?
    @NSManaged public var imapPort: Int32
    @NSManaged public var imapUseSSL: Bool
    @NSManaged public var smtpHost: String?
    @NSManaged public var smtpPort: Int32
    @NSManaged public var smtpUseSSL: Bool
    @NSManaged public var username: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var lastSyncAt: Date?
    @NSManaged public var colorHex: String?
    @NSManaged public var folders: NSSet?
}

public extension Account {
    @objc(addFoldersObject:)
    @NSManaged func addToFolders(_ value: Folder)

    @objc(removeFoldersObject:)
    @NSManaged func removeFromFolders(_ value: Folder)

    @objc(addFolders:)
    @NSManaged func addToFolders(_ values: NSSet)

    @objc(removeFolders:)
    @NSManaged func removeFromFolders(_ values: NSSet)
}
