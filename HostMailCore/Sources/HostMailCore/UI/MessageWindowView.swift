import CoreData
import SwiftUI

/// Wraps `MessageDetailView` for the standalone-window scene.
/// Resolves the message from a Core Data object-ID URI (URL is Codable so it
/// flows through SwiftUI's `WindowGroup(for: URL.self)` machinery).
public struct MessageWindowView: View {
    @Environment(\.managedObjectContext) private var context

    let messageURL: URL?

    public init(messageURL: URL?) {
        self.messageURL = messageURL
    }

    public var body: some View {
        Group {
            if let url = messageURL,
               let coordinator = context.persistentStoreCoordinator,
               let oid = coordinator.managedObjectID(forURIRepresentation: url),
               let msg = try? context.existingObject(with: oid) as? Message {
                MessageDetailView(message: msg)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.folder.fill")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Message not available")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
