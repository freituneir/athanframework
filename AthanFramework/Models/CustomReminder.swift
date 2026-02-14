import Foundation
import SwiftData

/// A user-created reminder beyond the 5 daily prayers.
/// Synced via iCloud (CloudKit container).
@Model
final class CustomReminder {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var scheduledTime: Date?

    var isRecurring: Bool = false

    /// Days of the week for recurrence. 1 = Sunday, 7 = Saturday.
    /// Empty means one-time (non-recurring).
    var recurrenceDays: [Int] = []

    var soundFileName: String = "default_reminder"
    var isEnabled: Bool = true
    var snoozeDurationSeconds: Int = 300

    /// When true, fires as an AlarmKit alarm (full-screen, breaks through Silent/Focus).
    var isUrgent: Bool = false

    /// EventKit event identifier for the corresponding calendar event.
    /// Used to update/delete the calendar event when the reminder changes.
    var calendarEventID: String?

    /// Whether the user has marked this reminder as completed.
    var isCompleted: Bool = false
    var completedAt: Date?

    init() {}
}
