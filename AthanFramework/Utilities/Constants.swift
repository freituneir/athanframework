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
        static let tintColorHex = "#7de8c9"      // Phthalo green (matches app theme)
    }

    enum Calendar {
        static let prayerCalendarTitle = "Prayer Times"
        static let eventDurationMinutes = 30
    }

    enum AlarmKit {
        static let usageDescription = "AthanFramework needs alarm access to wake you for prayer times"
    }

    enum AppGroup {
        static let suiteName = "group.com.athanframework.shared"
        static let completedKey = "completedItems"
        static let prayerTimesKey = "widgetPrayerTimes"
        static let nextPrayerKey = "widgetNextPrayer"
        static let themeKey = "selectedTheme"
        static let lastFiredAlarmKey = "lastFiredAlarm"       // String: prayer rawValue (legacy)
        static let lastFiredAlarmTimeKey = "lastFiredAlarmTime" // Double: timestamp (legacy)
        static let firedAlarmsKey = "firedAlarms"              // [String: Double]: prayer -> timestamp
        static let reminderDelayKey = "reminderDelay"          // Int: minutes
        /// Per-prayer reminder alarm IDs: "reminderAlarmID-{prayer}" -> UUID string
        static func reminderAlarmIDKey(for prayer: String) -> String { "reminderAlarmID-\(prayer)" }
        /// Per-prayer original fire dates: "reminderFireDate-{prayer}" -> Double (timestamp)
        static func reminderFireDateKey(for prayer: String) -> String { "reminderFireDate-\(prayer)" }
        /// Per-prayer followup alarm IDs: "followupAlarmID-{prayer}" -> UUID string
        static func followupAlarmIDKey(for prayer: String) -> String { "followupAlarmID-\(prayer)" }
    }
}
