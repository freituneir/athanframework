import Foundation

/// The five obligatory daily prayers in Islam.
enum Prayer: String, CaseIterable, Codable, Identifiable {
    case fajr
    case dhuhr
    case asr
    case maghrib
    case isha

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fajr:    return "Fajr"
        case .dhuhr:   return "Dhuhr"
        case .asr:     return "Asr"
        case .maghrib: return "Maghrib"
        case .isha:    return "Isha"
        }
    }

    /// Default snooze interval in seconds per prayer.
    /// Fajr is shorter (2 min) because it's the hardest to wake for.
    var defaultSnoozeDuration: Int {
        switch self {
        case .fajr: return 120
        default:    return 300
        }
    }

    /// Maps to the key name returned by the Aladhan API.
    var aladhanKey: String {
        switch self {
        case .fajr:    return "Fajr"
        case .dhuhr:   return "Dhuhr"
        case .asr:     return "Asr"
        case .maghrib: return "Maghrib"
        case .isha:    return "Isha"
        }
    }

    /// Sort order for display (chronological within a day).
    var sortOrder: Int {
        switch self {
        case .fajr:    return 0
        case .dhuhr:   return 1
        case .asr:     return 2
        case .maghrib: return 3
        case .isha:    return 4
        }
    }

    /// SF Symbol representing each prayer time.
    var sfSymbol: String {
        switch self {
        case .fajr:    return "sunrise.fill"
        case .dhuhr:   return "sun.max.fill"
        case .asr:     return "sun.haze.fill"
        case .maghrib: return "sunset.fill"
        case .isha:    return "moon.stars.fill"
        }
    }

    /// Descriptive subtitle for the prayer (useful in detail views).
    var subtitle: String {
        switch self {
        case .fajr:    return "Dawn prayer"
        case .dhuhr:   return "Midday prayer"
        case .asr:     return "Afternoon prayer"
        case .maghrib: return "Sunset prayer"
        case .isha:    return "Night prayer"
        }
    }

    /// Unique color hex representing the time of day for each prayer.
    var colorHex: String {
        switch self {
        case .fajr:    return "#2C3E7B"  // deep indigo — pre-dawn
        case .dhuhr:   return "#3A8DDE"  // bright sky blue — midday
        case .asr:     return "#D4792C"  // warm amber/orange — afternoon
        case .maghrib: return "#CF5C3F"  // coral/sunset
        case .isha:    return "#5B3A8C"  // deep purple — night
        }
    }

    /// Sunrise color hex (amber/gold).
    static let sunriseColorHex = "#E8A317"
}
