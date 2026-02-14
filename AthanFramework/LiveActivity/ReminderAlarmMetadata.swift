import Foundation
import AlarmKit

/// Custom metadata attached to urgent reminder alarms' Live Activity.
struct ReminderAlarmMetadata: AlarmMetadata {
    /// The reminder title for display context in the Live Activity.
    var reminderTitle: String
    /// When the alarm is scheduled to fire — used to show elapsed time after alerting.
    var fireDate: Date
    /// The entity key (e.g. "reminder-{UUID}") for shared completion state.
    var entityName: String

    init() {
        self.reminderTitle = ""
        self.fireDate = .now
        self.entityName = ""
    }

    init(title: String, fireDate: Date, entityName: String = "") {
        self.reminderTitle = title
        self.fireDate = fireDate
        self.entityName = entityName
    }
}
