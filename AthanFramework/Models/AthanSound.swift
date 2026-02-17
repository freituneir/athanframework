import Foundation
import ActivityKit

/// Available athan (call to prayer) audio recitations.
enum AthanSound: String, CaseIterable, Identifiable, Codable {
    case defaultTone = "default"
    case alafasy = "alafasy"
    case nafees = "nafees"
    case dubai = "dubai"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .defaultTone: return "Default Tone"
        case .alafasy:     return "Mishary Rashid Alafasy"
        case .nafees:      return "Ahmad al-Nafees"
        case .dubai:       return "Dubai (Alafasy)"
        }
    }

    /// The bundle filename (without extension) for this sound.
    var fileName: String? {
        switch self {
        case .defaultTone: return nil
        case .alafasy:     return "alafasy"
        case .nafees:      return "nafees"
        case .dubai:       return "dubai"
        }
    }

    /// AlarmKit/ActivityKit alert sound for this athan.
    var alertSound: AlertConfiguration.AlertSound {
        guard let fileName else { return .default }
        return .named("\(fileName).mp3")
    }
}
