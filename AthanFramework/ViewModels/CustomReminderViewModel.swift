import Foundation
import SwiftData

/// ViewModel for managing custom reminders (beyond the 5 daily prayers).
@Observable
@MainActor
final class CustomReminderViewModel {
    private let cloudContext: ModelContext
    private let calendarService: CalendarService
    private let alarmService: AlarmSchedulingService

    var reminders: [CustomReminder] = []

    init(cloudContext: ModelContext, calendarService: CalendarService, alarmService: AlarmSchedulingService) {
        self.cloudContext = cloudContext
        self.calendarService = calendarService
        self.alarmService = alarmService
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
        snoozeDuration: Int = AppConstants.Defaults.snoozeDurationOther,
        isUrgent: Bool = false
    ) async throws {
        let reminder = CustomReminder()
        reminder.title = title
        reminder.notes = notes
        reminder.scheduledTime = scheduledTime
        reminder.soundFileName = soundFileName
        reminder.isRecurring = isRecurring
        reminder.recurrenceDays = recurrenceDays
        reminder.snoozeDurationSeconds = snoozeDuration
        reminder.isUrgent = isUrgent

        cloudContext.insert(reminder)

        // Sync to calendar
        try await calendarService.syncCustomReminder(reminder)

        // Schedule AlarmKit alarm if urgent
        if isUrgent {
            try await alarmService.scheduleCustomReminderAlarm(reminder)
        }

        try cloudContext.save()
        loadReminders()
    }

    func deleteReminder(_ reminder: CustomReminder) async throws {
        if let eventID = reminder.calendarEventID {
            try await calendarService.deleteEvent(identifier: eventID)
        }
        // Cancel AlarmKit alarm if urgent
        if reminder.isUrgent {
            try await alarmService.cancelCustomReminderAlarm(reminderID: reminder.id)
        }
        cloudContext.delete(reminder)
        try cloudContext.save()
        loadReminders()
    }

    func toggleReminder(_ reminder: CustomReminder) {
        reminder.isEnabled.toggle()
        try? cloudContext.save()

        // Schedule or cancel AlarmKit alarm for urgent reminders
        if reminder.isUrgent {
            Task {
                if reminder.isEnabled {
                    try? await alarmService.scheduleCustomReminderAlarm(reminder)
                } else {
                    try? await alarmService.cancelCustomReminderAlarm(reminderID: reminder.id)
                }
            }
        }
    }
}
