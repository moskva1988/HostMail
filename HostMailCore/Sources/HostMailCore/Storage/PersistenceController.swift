import CoreData
import Foundation

public final class PersistenceController: @unchecked Sendable {
    public static let shared = PersistenceController()

    public static let cloudKitContainerIdentifier = "iCloud.com.host.mail"
    public static let modelName = "HostMailStore"

    public let container: NSPersistentCloudKitContainer

    public init(inMemory: Bool = false) {
        guard let modelURL = Bundle.module.url(forResource: Self.modelName, withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("\(Self.modelName) Core Data model not found in module bundle")
        }

        container = NSPersistentCloudKitContainer(name: Self.modelName, managedObjectModel: model)

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("No persistent store description available")
        }

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        }

        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        if !inMemory {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerIdentifier
            )
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                assertionFailure("Core Data load error: \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    public var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    public func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
}

public extension PersistenceController {
    static let preview: PersistenceController = PersistenceController(inMemory: true)
}
