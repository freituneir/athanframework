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
    /// Snooze interval in seconds — read by SnoozePrayerIntent to schedule the re-fire.
    var snoozeDurationSeconds: Int

    init() {
        self.prayerName = ""
        self.fireDate = .now
        self.nextPrayerName = ""
        self.snoozeDurationSeconds = 300
    }

    init(prayer: Prayer, fireDate: Date, nextPrayer: Prayer? = nil, snoozeDurationSeconds: Int = 300) {
        self.prayerName = prayer.rawValue
        self.fireDate = fireDate
        self.nextPrayerName = nextPrayer?.rawValue ?? ""
        self.snoozeDurationSeconds = snoozeDurationSeconds
    }
}
