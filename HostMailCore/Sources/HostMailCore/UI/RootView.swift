import CoreData
import SwiftUI

public struct RootView: View {
    @Environment(\.managedObjectContext) private var context
    @State private var storeStatus: String = "Loading store…"

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("HostMail")
                .font(.largeTitle.weight(.bold))
            Text("v\(HostMailCore.version) — skeleton")
                .foregroundStyle(.secondary)
            Divider()
                .padding(.horizontal, 40)
            Label(storeStatus, systemImage: "externaldrive.badge.icloud")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(minWidth: 320, minHeight: 480)
        .task { await refreshStoreStatus() }
    }

    private func refreshStoreStatus() async {
        let request: NSFetchRequest<Account> = Account.fetchRequest()
        let count: Int = await context.perform {
            (try? context.count(for: request)) ?? 0
        }
        storeStatus = "Core Data + CloudKit ready — \(count) account(s)"
    }
}

#Preview {
    RootView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
