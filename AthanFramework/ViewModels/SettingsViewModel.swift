import Foundation
import SwiftData

/// ViewModel for the settings screen.
@Observable
@MainActor
final class SettingsViewModel {
    private let cloudContext: ModelContext

    var preferences: UserPreferences?
    var availableCalendars: [(id: String, title: String)] = []

    init(cloudContext: ModelContext) {
        self.cloudContext = cloudContext
        loadPreferences()
    }

    func loadPreferences() {
        let descriptor = FetchDescriptor<UserPreferences>()
        preferences = try? cloudContext.fetch(descriptor).first
    }

    func updateCalculationMethod(_ method: CalculationMethod) {
        preferences?.calculationMethod = method
        try? cloudContext.save()
    }

    func updateSchool(_ school: AsrSchool) {
        preferences?.school = school
        try? cloudContext.save()
    }

    func toggleCalendarSync(_ enabled: Bool) {
        preferences?.calendarSyncEnabled = enabled
        try? cloudContext.save()
    }

    func selectCalendar(id: String) {
        preferences?.selectedCalendarID = id
        try? cloudContext.save()
    }

    func toggleAutoLocation(_ enabled: Bool) {
        preferences?.useAutoLocation = enabled
        try? cloudContext.save()
    }

    func updateManualLocation(latitude: Double, longitude: Double, name: String) {
        preferences?.latitude = latitude
        preferences?.longitude = longitude
        preferences?.locationName = name
        preferences?.useAutoLocation = false
        try? cloudContext.save()
    }
}
