import CoreData
import Foundation

@objc(Folder)
public final class Folder: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Folder> {
        NSFetchRequest<Folder>(entityName: "Folder")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var path: String?
    @NSManaged public var role: String?
    @NSManaged public var uidValidity: Int64
    @NSManaged public var unreadCount: Int32
    @NSManaged public var totalCount: Int32
    @NSManaged public var account: Account?
    @NSManaged public var messages: NSSet?
}

public extension Folder {
    @objc(addMessagesObject:)
    @NSManaged func addToMessages(_ value: Message)

    @objc(removeMessagesObject:)
    @NSManaged func removeFromMessages(_ value: Message)

    @objc(addMessages:)
    @NSManaged func addToMessages(_ values: NSSet)

    @objc(removeMessages:)
    @NSManaged func removeFromMessages(_ values: NSSet)
}
