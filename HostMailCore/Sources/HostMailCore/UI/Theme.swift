import SwiftUI

public enum HostTheme {
    // Host* family palette — HostMail teal, distinct from HostCheck indigo
    // (#6366f1) so the two apps read as siblings, not duplicates. Teal-600
    // (Tailwind) sits in the calm/communication colour zone, contrasts well
    // with white envelope artwork and dark surfaces.
    public static let accent      = Color(red: 0.05, green: 0.58, blue: 0.53) // ≈ #0D9488
    public static let accentDeep  = Color(red: 0.06, green: 0.46, blue: 0.43) // hover/active ≈ #0F766E
    public static let accentSoft  = Color(red: 0.05, green: 0.58, blue: 0.53).opacity(0.18)

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
