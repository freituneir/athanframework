import SwiftUI

/// Phthalo Green design system — colors and tokens from the HTML mockup designs.
enum AthanTheme {
    // MARK: - Background
    static let bgDark = Color(hex: "#051a17")
    static let bgMid = Color(hex: "#072420")
    static let bgLight = Color(hex: "#0a2e2a")

    static let backgroundGradient = LinearGradient(
        colors: [bgLight, bgMid, bgDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Accent
    static let accent = Color(hex: "#7de8c9")
    static let accentDeep = Color(hex: "#3aaf8a")

    // MARK: - Card
    static let cardBackground = Color(hex: "#7de8c9").opacity(0.03)
    static let cardBorder = Color(hex: "#7de8c9").opacity(0.06)
    static let cardEdgeHighlight = Color(hex: "#7de8c9").opacity(0.25)

    // MARK: - Live Activity
    static let liveActivityBg = Color(red: 20.0 / 255, green: 50.0 / 255, blue: 44.0 / 255)
}
