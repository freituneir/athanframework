import Foundation
import AlarmKit

/// Custom metadata attached to each prayer alarm's Live Activity.
/// AlarmKit requires a concrete `AlarmMetadata` type even if no extra state is needed.
struct PrayerAlarmMetadata: AlarmMetadata {
    /// The raw value of the `Prayer` enum so the Live Activity can display context.
    var prayerName: String
    /// When the alarm is scheduled to fire — used to detect post-alert phase.
    var fireDate: Date
    /// The raw value of the next `Prayer` after this one (for post-alert countdown title).
    var nextPrayerName: String
    /// Pre-formatted time string for the next prayer, e.g. "7:05 PM".
    var nextPrayerTimeString: String
    /// Snooze interval in seconds — used as postAlert for AlarmKit native snooze.
    var snoozeDurationSeconds: Int
    /// Actual preAlert countdown window in seconds — used by LAProgressBar for accurate fill.
    var preAlertSeconds: Double
    /// The actual prayer time from the API, without user offset.
    /// Used for count-up timer display — shows time since prayer actually started.
    var rawPrayerTime: Date

    init() {
        self.prayerName = ""
        self.fireDate = .now
        self.nextPrayerName = ""
        self.nextPrayerTimeString = ""
        self.snoozeDurationSeconds = 300
        self.preAlertSeconds = 300
        self.rawPrayerTime = .now
    }

    init(prayer: Prayer, fireDate: Date, rawPrayerTime: Date? = nil, nextPrayer: Prayer? = nil, nextPrayerTimeString: String = "", snoozeDurationSeconds: Int = 300, preAlertSeconds: Double = 300) {
        self.prayerName = prayer.rawValue
        self.fireDate = fireDate
        self.rawPrayerTime = rawPrayerTime ?? fireDate
        self.nextPrayerName = nextPrayer?.rawValue ?? ""
        self.nextPrayerTimeString = nextPrayerTimeString
        self.snoozeDurationSeconds = snoozeDurationSeconds
        self.preAlertSeconds = preAlertSeconds
    }
}
