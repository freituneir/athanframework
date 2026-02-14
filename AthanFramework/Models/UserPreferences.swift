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
}
