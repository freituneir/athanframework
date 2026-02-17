import SwiftUI

// MARK: - Color Theme Enum

enum ColorTheme: String, CaseIterable, Identifiable, Codable {
    case green
    case blue
    case red

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .green: return "Phthalo Green"
        case .blue:  return "Ocean Blue"
        case .red:   return "Burgundy Red"
        }
    }

    /// Preview swatch color for the theme picker.
    var swatchColor: Color {
        switch self {
        case .green: return Color(hex: "#7de8c9")
        case .blue:  return Color(hex: "#7db8e8")
        case .red:   return Color(hex: "#e87d8c")
        }
    }

    /// Alternate icon name for `setAlternateIconName`. Nil = primary (green).
    var alternateIconName: String? {
        switch self {
        case .green: return nil
        case .blue:  return "AppIconBlue"
        case .red:   return "AppIconRed"
        }
    }
}

// MARK: - Athan Theme (computed from active theme)

enum AthanTheme {

    /// Reads the active theme from App Group UserDefaults.
    /// Falls back to `.green` if not set.
    static var current: ColorTheme {
        guard let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName),
              let raw = suite.string(forKey: AppConstants.AppGroup.themeKey),
              let theme = ColorTheme(rawValue: raw) else {
            return .green
        }
        return theme
    }

    // MARK: - Background

    static var bgDark: Color {
        switch current {
        case .green: return Color(hex: "#051a17")
        case .blue:  return Color(hex: "#050e1a")
        case .red:   return Color(hex: "#1a0508")
        }
    }

    static var bgMid: Color {
        switch current {
        case .green: return Color(hex: "#072420")
        case .blue:  return Color(hex: "#071724")
        case .red:   return Color(hex: "#240710")
        }
    }

    static var bgLight: Color {
        switch current {
        case .green: return Color(hex: "#0a2e2a")
        case .blue:  return Color(hex: "#0a202e")
        case .red:   return Color(hex: "#2e0a15")
        }
    }

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [bgLight, bgMid, bgDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Accent

    static var accent: Color {
        switch current {
        case .green: return Color(hex: "#7de8c9")
        case .blue:  return Color(hex: "#7db8e8")
        case .red:   return Color(hex: "#e87d8c")
        }
    }

    static var accentDeep: Color {
        switch current {
        case .green: return Color(hex: "#3aaf8a")
        case .blue:  return Color(hex: "#3a72af")
        case .red:   return Color(hex: "#af3a4a")
        }
    }

    // MARK: - Card

    static var cardBackground: Color { accent.opacity(0.03) }
    static var cardBorder: Color { accent.opacity(0.06) }
    static var cardEdgeHighlight: Color { accent.opacity(0.25) }

    // MARK: - Text

    /// Soft warm gold — headings, prayer names, countdown digits, date display.
    static let textPrimary = Color(hex: "#d4af37").opacity(0.55)

    /// Dim white — captions, timestamps, secondary labels.
    static let textSecondary = Color.white.opacity(0.4)

    // MARK: - Live Activity

    static var liveActivityBg: Color {
        switch current {
        case .green: return Color(red: 20.0/255, green: 50.0/255, blue: 44.0/255)
        case .blue:  return Color(red: 20.0/255, green: 38.0/255, blue: 55.0/255)
        case .red:   return Color(red: 55.0/255, green: 20.0/255, blue: 28.0/255)
        }
    }
}
