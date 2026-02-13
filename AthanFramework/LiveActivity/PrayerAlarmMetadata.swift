import AlarmKit

/// Custom metadata attached to each prayer alarm's Live Activity.
/// AlarmKit requires a concrete `AlarmMetadata` type even if no extra state is needed.
struct PrayerAlarmMetadata: AlarmMetadata {
    /// The raw value of the `Prayer` enum so the Live Activity can display context.
    var prayerName: String

    init() {
        self.prayerName = ""
    }

    init(prayer: Prayer) {
        self.prayerName = prayer.rawValue
    }
}
