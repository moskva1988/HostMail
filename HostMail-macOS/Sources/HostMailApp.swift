import SwiftUI
import HostMailCore

@main
struct HostMailApp: App {
    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.viewContext)
        }
        .windowResizability(.contentSize)

        // Standalone message window — opened by double-clicking a row.
        // The value is the Core Data object-ID URI; URL is Codable, which
        // is what WindowGroup(for:) requires.
        WindowGroup("Message", id: "message", for: URL.self) { $messageURL in
            MessageWindowView(messageURL: messageURL)
                .environment(\.managedObjectContext, persistence.viewContext)
        }
    }
}
