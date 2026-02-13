import Foundation
import SwiftData

/// ViewModel for managing custom reminders (beyond the 5 daily prayers).
@Observable
@MainActor
final class CustomReminderViewModel {
    private let cloudContext: ModelContext
    private let calendarService: CalendarService

    var reminders: [CustomReminder] = []

    init(cloudContext: ModelContext, calendarService: CalendarService) {
        self.cloudContext = cloudContext
        self.calendarService = calendarService
    }

    func loadReminders() {
        let descriptor = FetchDescriptor<CustomReminder>(
            sortBy: [SortDescriptor(\.scheduledTime)]
        )
        reminders = (try? cloudContext.fetch(descriptor)) ?? []
    }

    func addReminder(
        title: String,
        notes: String = "",
        scheduledTime: Date,
        soundFileName: String = AppConstants.Defaults.defaultReminderSoundName,
        isRecurring: Bool = false,
        recurrenceDays: [Int] = [],
        snoozeDuration: Int = AppConstants.Defaults.snoozeDurationOther
    ) async throws {
        let reminder = CustomReminder()
        reminder.title = title
        reminder.notes = notes
        reminder.scheduledTime = scheduledTime
        reminder.soundFileName = soundFileName
        reminder.isRecurring = isRecurring
        reminder.recurrenceDays = recurrenceDays
        reminder.snoozeDurationSeconds = snoozeDuration

        cloudContext.insert(reminder)

        // Sync to calendar
        try await calendarService.syncCustomReminder(reminder)

        try cloudContext.save()
        loadReminders()
    }

    func deleteReminder(_ reminder: CustomReminder) async throws {
        if let eventID = reminder.calendarEventID {
            try await calendarService.deleteEvent(identifier: eventID)
        }
        cloudContext.delete(reminder)
        try cloudContext.save()
        loadReminders()
    }

    func toggleReminder(_ reminder: CustomReminder) {
        reminder.isEnabled.toggle()
        try? cloudContext.save()
    }
}
