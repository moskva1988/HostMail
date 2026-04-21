import SwiftUI

public struct RootView: View {
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
        }
        .padding()
        .frame(minWidth: 320, minHeight: 480)
    }
}

#Preview {
    RootView()
}
