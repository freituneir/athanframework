import Foundation
import SwiftData

/// Per-prayer alarm settings. Each of the 5 prayers has one of these.
/// Synced via iCloud (CloudKit container).
@Model
final class PrayerAlarmConfig {
    var id: UUID = UUID()

    /// Which prayer this config is for (stored as raw string for CloudKit compat).
    var prayerName: String = ""

    var isEnabled: Bool = true

    /// Audio file name (without extension) from the app bundle.
    var soundFileName: String = "default_athan"

    /// Snooze interval in seconds. AlarmKit's `postAlert` duration.
    /// Alarm re-fires after this many seconds if not dismissed via "Done".
    var snoozeDurationSeconds: Int = 300

    /// Offset in minutes from the actual prayer time.
    /// Positive = after, Negative = before (e.g., -30 for 30 min before Fajr).
    var offsetMinutes: Int = 0

    /// When true (Fajr only), offsetMinutes is relative to Sunrise instead of Fajr time.
    /// e.g., offsetMinutes = -30 means "30 minutes before sunrise".
    var usesSunriseOffset: Bool = false

    var escalationEnabled: Bool = true

    /// Tint color as hex string (SwiftData can't store Color directly).
    var tintColorHex: String = "#1B7A3D"

    init() {}

    /// Convenience initializer for setting up defaults per prayer.
    convenience init(prayer: Prayer) {
        self.init()
        self.prayerName = prayer.rawValue
        self.snoozeDurationSeconds = prayer.defaultSnoozeDuration
    }

    /// The Prayer enum value for this config.
    var prayer: Prayer? {
        Prayer(rawValue: prayerName)
    }
}
