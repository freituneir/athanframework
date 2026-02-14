import AlarmKit

/// Custom metadata attached to urgent reminder alarms' Live Activity.
struct ReminderAlarmMetadata: AlarmMetadata {
    /// The reminder title for display context in the Live Activity.
    var reminderTitle: String

    init() {
        self.reminderTitle = ""
    }

    init(title: String) {
        self.reminderTitle = title
    }
}
