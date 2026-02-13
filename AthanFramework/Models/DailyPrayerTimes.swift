import Foundation
import SwiftData

/// Cached prayer times for a single day and location, fetched from the Aladhan API.
/// Stored as absolute `Date` objects so they can be handed directly to AlarmKit's
/// `Alarm.Schedule.fixed()` without timezone conversion.
@Model
final class DailyPrayerTimes {
    var id: UUID = UUID()

    /// The calendar day (normalized to midnight local time).
    var date: Date = Date()

    var latitude: Double = 0.0
    var longitude: Double = 0.0
    var timezone: String = ""

    /// Aladhan calculation method ID (e.g., 2 = ISNA, 3 = MWL).
    var calculationMethod: Int = 2

    // Prayer times as absolute Date objects
    var fajr: Date?
    var sunrise: Date?
    var dhuhr: Date?
    var asr: Date?
    var maghrib: Date?
    var isha: Date?

    var fetchedAt: Date = Date()
    var hijriDate: String = ""
    var gregorianDate: String = ""

    init() {}

    /// Returns the time for a given prayer, or nil if not available.
    func time(for prayer: Prayer) -> Date? {
        switch prayer {
        case .fajr:    return fajr
        case .dhuhr:   return dhuhr
        case .asr:     return asr
        case .maghrib: return maghrib
        case .isha:    return isha
        }
    }
}
