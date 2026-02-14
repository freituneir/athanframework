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
        syncSharedReminderCompletions()
    }

    /// Reads reminder completions written by StopPrayerIntent in the widget extension.
    private func syncSharedReminderCompletions() {
        guard let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) else { return }
        guard var completed = suite.dictionary(forKey: AppConstants.AppGroup.completedKey) as? [String: Double] else { return }

        var processed: [String] = []

        for (key, timestamp) in completed {
            // Reminder keys are formatted as "reminder-{UUID}"
            guard key.hasPrefix("reminder-") else { continue }
            let uuidStr = String(key.dropFirst("reminder-".count))
            guard let reminderID = UUID(uuidString: uuidStr) else { continue }

            if let reminder = reminders.first(where: { $0.id == reminderID }),
               !reminder.isCompleted {
                reminder.isCompleted = true
                reminder.completedAt = Date(timeIntervalSince1970: timestamp)
            }

            processed.append(key)
        }

        if !processed.isEmpty {
            for key in processed {
                completed.removeValue(forKey: key)
            }
            suite.set(completed, forKey: AppConstants.AppGroup.completedKey)
            try? cloudContext.save()
        }
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

    /// Toggle completion state for a custom reminder.
    /// When marking complete, also cancels the Live Activity alarm.
    func toggleCompletion(_ reminder: CustomReminder) {
        reminder.isCompleted.toggle()
        reminder.completedAt = reminder.isCompleted ? Date() : nil
        try? cloudContext.save()

        if reminder.isCompleted && reminder.isUrgent {
            Task {
                try? await alarmService.cancelCustomReminderAlarm(reminderID: reminder.id)
            }
        }
    }

    func updateReminder(
        _ reminder: CustomReminder,
        title: String,
        notes: String,
        scheduledTime: Date,
        isRecurring: Bool,
        recurrenceDays: [Int],
        snoozeDuration: Int,
        isUrgent: Bool
    ) async throws {
        let wasUrgent = reminder.isUrgent

        reminder.title = title
        reminder.notes = notes
        reminder.scheduledTime = scheduledTime
        reminder.isRecurring = isRecurring
        reminder.recurrenceDays = recurrenceDays
        reminder.snoozeDurationSeconds = snoozeDuration
        reminder.isUrgent = isUrgent

        // Re-sync calendar event
        try await calendarService.syncCustomReminder(reminder)

        // Handle alarm changes
        if wasUrgent {
            try await alarmService.cancelCustomReminderAlarm(reminderID: reminder.id)
        }
        if isUrgent && reminder.isEnabled {
            try await alarmService.scheduleCustomReminderAlarm(reminder)
        }

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
