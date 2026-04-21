import CoreData
import Foundation

@objc(Message)
public final class Message: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Message> {
        NSFetchRequest<Message>(entityName: "Message")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var uid: Int64
    @NSManaged public var messageID: String?
    @NSManaged public var subject: String?
    @NSManaged public var from: String?
    @NSManaged public var to: String?
    @NSManaged public var cc: String?
    @NSManaged public var date: Date?
    @NSManaged public var preview: String?
    @NSManaged public var bodyPlain: String?
    @NSManaged public var bodyHTML: String?
    @NSManaged public var flags: Int32
    @NSManaged public var hasAttachments: Bool
    @NSManaged public var fetchedAt: Date?
    @NSManaged public var folder: Folder?
}

public struct MessageFlags: OptionSet, Sendable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }

    public static let seen       = MessageFlags(rawValue: 1 << 0)
    public static let answered   = MessageFlags(rawValue: 1 << 1)
    public static let flagged    = MessageFlags(rawValue: 1 << 2)
    public static let deleted    = MessageFlags(rawValue: 1 << 3)
    public static let draft      = MessageFlags(rawValue: 1 << 4)
    public static let recent     = MessageFlags(rawValue: 1 << 5)
}
