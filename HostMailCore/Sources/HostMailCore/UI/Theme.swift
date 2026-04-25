import SwiftUI

public enum HostTheme {
    // Brand palette aligned with HostCheck (Host* family).
    // Primary purple — buttons, accents, sync indicators.
    public static let accent      = Color(red: 0.42, green: 0.42, blue: 0.91) // ≈ #6B6BE8
    public static let accentDeep  = Color(red: 0.32, green: 0.32, blue: 0.78) // hover/active
    public static let accentSoft  = Color(red: 0.42, green: 0.42, blue: 0.91).opacity(0.18)

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
