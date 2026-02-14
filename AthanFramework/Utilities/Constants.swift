import Foundation

enum AppConstants {
    enum API {
        static let aladhanBaseURL = "https://api.aladhan.com/v1"
        /// Monthly calendar endpoint: /calendar/{year}/{month}
        static let calendarEndpoint = "/calendar"
    }

    enum Defaults {
        static let calculationMethod = CalculationMethod.isna
        static let school = AsrSchool.shafi
        static let snoozeDurationFajr = 120      // 2 minutes
        static let snoozeDurationOther = 300     // 5 minutes
        static let defaultSoundName = "default_athan"
        static let defaultReminderSoundName = "default_reminder"
        static let tintColorHex = "#2D5BA0"      // Royal blue (matches app icon)
    }

    enum Calendar {
        static let prayerCalendarTitle = "Prayer Times"
        static let eventDurationMinutes = 30
    }

    enum AlarmKit {
        static let usageDescription = "AthanFramework needs alarm access to wake you for prayer times"
    }
}
