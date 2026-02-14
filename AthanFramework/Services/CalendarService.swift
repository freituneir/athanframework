import EventKit
import Foundation

/// Manages calendar integration via EventKit, creating and syncing prayer time
/// events and custom reminders to the user's calendar.
@Observable
@MainActor
final class CalendarService {

    // MARK: - Properties

    private let store = EKEventStore()

    /// The calendar selected by the user for prayer events.
    /// Falls back to the app-created "Prayer Times" calendar.
    var selectedCalendarIdentifier: String?

    /// Whether the user has granted full calendar access.
    private(set) var hasAccess = false

    // MARK: - Access

    /// Requests full calendar access (iOS 17+). Returns `true` if granted.
    @discardableResult
    func requestAccess() async throws -> Bool {
        let granted = try await store.requestFullAccessToEvents()
        hasAccess = granted
        return granted
    }

    // MARK: - Calendar Management

    /// Returns the user-selected calendar, or creates a dedicated "Prayer Times"
    /// calendar if none is selected.
    func getOrCreatePrayerCalendar() throws -> EKCalendar {
        // Return the user-selected calendar if it still exists.
        if let identifier = selectedCalendarIdentifier,
           let calendar = store.calendar(withIdentifier: identifier) {
            return calendar
        }

        // Look for an existing "Prayer Times" calendar we created previously.
        let title = AppConstants.Calendar.prayerCalendarTitle
        if let existing = store.calendars(for: .event).first(where: { $0.title == title }) {
            selectedCalendarIdentifier = existing.calendarIdentifier
            return existing
        }

        // Create a new local calendar.
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = title

        // Prefer a local source; fall back to the default calendar's source.
        if let localSource = store.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
        } else if let defaultSource = store.defaultCalendarForNewEvents?.source {
            calendar.source = defaultSource
        }

        try store.saveCalendar(calendar, commit: true)
        selectedCalendarIdentifier = calendar.calendarIdentifier
        return calendar
    }

    /// Lists all writable calendars the user can choose from.
    func availableCalendars() -> [EKCalendar] {
        store.calendars(for: .event).filter { $0.allowsContentModifications }
    }

    // MARK: - Prayer Event Sync

    /// Creates or updates calendar events for all five prayers on a given day.
    func syncPrayerEvents(for day: DailyPrayerTimes) async throws {
        let calendar = try getOrCreatePrayerCalendar()

        for prayer in Prayer.allCases {
            guard let prayerTime = day.time(for: prayer) else { continue }
            try syncSinglePrayerEvent(prayer: prayer, time: prayerTime, calendar: calendar)
        }
    }

    /// Syncs calendar events for multiple days at once (used for 30-day lookahead).
    func syncPrayerEvents(for days: [DailyPrayerTimes]) async throws {
        let calendar = try getOrCreatePrayerCalendar()

        for day in days {
            for prayer in Prayer.allCases {
                guard let prayerTime = day.time(for: prayer) else { continue }
                try syncSinglePrayerEvent(prayer: prayer, time: prayerTime, calendar: calendar)
            }
        }
    }

    // MARK: - Custom Reminder Sync

    /// Creates or updates a calendar event for a custom reminder.
    /// Stores the resulting `EKEvent.eventIdentifier` on the reminder model.
    func syncCustomReminder(_ reminder: CustomReminder) async throws {
        let calendar = try getOrCreatePrayerCalendar()

        guard let scheduledTime = reminder.scheduledTime else { return }

        // Try to update existing event if we have an identifier.
        if let eventID = reminder.calendarEventID,
           let existing = store.event(withIdentifier: eventID) {
            existing.title = reminder.title
            existing.startDate = scheduledTime
            existing.endDate = scheduledTime.addingTimeInterval(
                Double(AppConstants.Calendar.eventDurationMinutes) * 60
            )
            existing.notes = "AthanFramework"
            existing.calendar = calendar

            configureRecurrence(for: existing, reminder: reminder)
            try store.save(existing, span: .futureEvents, commit: true)
            return
        }

        // Check for duplicates before creating.
        if let duplicate = findExistingEvent(
            title: reminder.title,
            near: scheduledTime,
            in: calendar
        ) {
            reminder.calendarEventID = duplicate.eventIdentifier
            return
        }

        // Create a new event.
        let event = EKEvent(eventStore: store)
        event.title = reminder.title
        event.startDate = scheduledTime
        event.endDate = scheduledTime.addingTimeInterval(
            Double(AppConstants.Calendar.eventDurationMinutes) * 60
        )
        event.notes = "AthanFramework"
        event.calendar = calendar

        configureRecurrence(for: event, reminder: reminder)
        try store.save(event, span: .futureEvents, commit: true)
        reminder.calendarEventID = event.eventIdentifier
    }

    // MARK: - Delete

    /// Removes a calendar event by its EventKit identifier.
    func deleteEvent(identifier: String) async throws {
        guard let event = store.event(withIdentifier: identifier) else { return }
        try store.remove(event, span: .futureEvents, commit: true)
    }

    // MARK: - Private Helpers

    /// Creates or updates a single prayer event, deduplicating by title and time window.
    private func syncSinglePrayerEvent(
        prayer: Prayer,
        time: Date,
        calendar: EKCalendar
    ) throws {
        let title = "\(prayer.displayName) Prayer"
        let duration = Double(AppConstants.Calendar.eventDurationMinutes) * 60

        // Check for an existing event within the deduplication window.
        if let existing = findExistingEvent(title: title, near: time, in: calendar) {
            // Update in case the prayer time shifted slightly.
            existing.startDate = time
            existing.endDate = time.addingTimeInterval(duration)
            try store.save(existing, span: .thisEvent, commit: true)
            return
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = time
        event.endDate = time.addingTimeInterval(duration)
        event.notes = "AthanFramework"
        event.calendar = calendar

        try store.save(event, span: .thisEvent, commit: true)
    }

    /// Finds an existing event matching `title` within +/-60 seconds of `date`
    /// in the specified calendar, used for deduplication.
    private func findExistingEvent(
        title: String,
        near date: Date,
        in calendar: EKCalendar
    ) -> EKEvent? {
        let window: TimeInterval = 60
        let start = date.addingTimeInterval(-window)
        let end = date.addingTimeInterval(window)

        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: [calendar]
        )

        return store.events(matching: predicate).first { event in
            event.title == title && event.notes == "AthanFramework"
        }
    }

    /// Configures weekly recurrence rules on an event based on a CustomReminder.
    private func configureRecurrence(for event: EKEvent, reminder: CustomReminder) {
        // Clear existing rules.
        event.recurrenceRules?.forEach { event.removeRecurrenceRule($0) }

        guard reminder.isRecurring, !reminder.recurrenceDays.isEmpty else { return }

        let daysOfWeek = reminder.recurrenceDays.compactMap { dayNumber -> EKRecurrenceDayOfWeek? in
            guard (1...7).contains(dayNumber) else { return nil }
            return EKRecurrenceDayOfWeek(EKWeekday(rawValue: dayNumber)!)
        }

        let rule = EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: 1,
            daysOfTheWeek: daysOfWeek,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )
        event.addRecurrenceRule(rule)
    }
}
