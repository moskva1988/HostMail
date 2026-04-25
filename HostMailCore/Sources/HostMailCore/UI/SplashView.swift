import SwiftUI

public struct SplashView: View {
    @State private var iconScale: CGFloat = 0.85
    @State private var iconOpacity: Double = 0.0

    public init() {}

    public var body: some View {
        ZStack {
            HostTheme.accent
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 76, weight: .semibold))
                    .foregroundStyle(.white)
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)
                Text("HostMail")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(iconOpacity)
                Text("Smart Email")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .opacity(iconOpacity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
        }
    }
}

#Preview { SplashView() }
