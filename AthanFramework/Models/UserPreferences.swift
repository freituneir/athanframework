import Foundation
import SwiftData

/// Global app settings. Only one record should exist at a time.
/// Synced via iCloud (CloudKit container).
@Model
final class UserPreferences {
    var id: UUID = UUID()

    // Location
    var latitude: Double = 0.0
    var longitude: Double = 0.0
    var locationName: String = ""
    var useAutoLocation: Bool = true

    // Calculation
    var calculationMethodRaw: Int = CalculationMethod.isna.rawValue
    var schoolRaw: Int = AsrSchool.shafi.rawValue

    // Calendar
    var calendarSyncEnabled: Bool = false
    var calendarSyncAhead: Bool = false
    var selectedCalendarID: String = ""

    // Sound
    var selectedAthanSoundRaw: String = AthanSound.defaultTone.rawValue

    // Theme
    var selectedThemeRaw: String = ColorTheme.green.rawValue

    // Reminder LA: how many minutes after prayer time before the "Pray Now" LA appears
    var reminderDelayMinutes: Int = 5

    // Tracking
    var onboardingCompleted: Bool = false
    var lastRefreshDate: Date?

    init() {}

    var calculationMethod: CalculationMethod {
        get { CalculationMethod(rawValue: calculationMethodRaw) ?? .isna }
        set { calculationMethodRaw = newValue.rawValue }
    }

    var school: AsrSchool {
        get { AsrSchool(rawValue: schoolRaw) ?? .shafi }
        set { schoolRaw = newValue.rawValue }
    }

    var selectedAthanSound: AthanSound {
        get { AthanSound(rawValue: selectedAthanSoundRaw) ?? .defaultTone }
        set { selectedAthanSoundRaw = newValue.rawValue }
    }

    var selectedTheme: ColorTheme {
        get { ColorTheme(rawValue: selectedThemeRaw) ?? .green }
        set { selectedThemeRaw = newValue.rawValue }
    }
}
