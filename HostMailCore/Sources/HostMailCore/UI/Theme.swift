import SwiftUI

public enum HostTheme {
    // Host* family brand color — exact HostCheck indigo. Same hex values as
    // /root/HostCheck (Color(hex: "6366f1") in their views).
    public static let accent      = Color(red: 0.388, green: 0.400, blue: 0.945) // #6366F1 Indigo-500
    public static let accentDeep  = Color(red: 0.310, green: 0.275, blue: 0.898) // #4F46E5 Indigo-600
    public static let accentSoft  = Color(red: 0.388, green: 0.400, blue: 0.945).opacity(0.18)

    // Surfaces
    public static let cardBg       = Color(.sRGB, red: 0.10, green: 0.10, blue: 0.13, opacity: 1.0)
    public static let cardBgRaised = Color(.sRGB, red: 0.13, green: 0.13, blue: 0.16, opacity: 1.0)

    // Status colors (HostCheck convention)
    public static let successGreen = Color(red: 0.32, green: 0.85, blue: 0.55)
    public static let warningAmber = Color(red: 1.00, green: 0.78, blue: 0.20)
    public static let errorRed     = Color(red: 0.97, green: 0.40, blue: 0.40)

    public static let cornerRadius: CGFloat = 12
}

public extension View {
    func hostCard() -> some View {
        self
            .padding(12)
            .background(HostTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: HostTheme.cornerRadius, style: .continuous))
    }

    func hostBrandTint() -> some View {
        self.tint(HostTheme.accent)
    }
}
