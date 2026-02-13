import Foundation

extension DateFormatter {
    /// Formats a prayer time for display, e.g., "5:23 AM".
    static let prayerTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    /// Short date format, e.g., "Feb 13, 2026".
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

extension Date {
    /// Returns the date normalized to midnight in the current timezone.
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// True if this date is today (comparing calendar day only).
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    /// True if this date is in the past.
    var isPast: Bool {
        self < Date()
    }
}
