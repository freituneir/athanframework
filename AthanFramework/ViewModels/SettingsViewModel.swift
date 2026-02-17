import Foundation
import SwiftData
import UIKit
import WidgetKit

/// ViewModel for the settings screen.
@Observable
@MainActor
final class SettingsViewModel {
    private let cloudContext: ModelContext
    private let alarmService: AlarmSchedulingService?

    var preferences: UserPreferences?
    var availableCalendars: [(id: String, title: String)] = []

    init(cloudContext: ModelContext, alarmService: AlarmSchedulingService? = nil) {
        self.cloudContext = cloudContext
        self.alarmService = alarmService
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

    func toggleCalendarSyncAhead(_ enabled: Bool) {
        preferences?.calendarSyncAhead = enabled
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

    func updateAthanSound(_ sound: AthanSound) {
        preferences?.selectedAthanSound = sound
        try? cloudContext.save()

        // Force reschedule all alarms so the new sound takes effect immediately
        if let alarmService {
            _ = alarmService.stopAllAlarms()
            // Reconcile will reschedule with updated config on next refresh
        }
    }

    func updateTheme(_ theme: ColorTheme) {
        preferences?.selectedTheme = theme
        try? cloudContext.save()

        // Write to App Group so widgets and Live Activities pick up the new theme
        if let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) {
            suite.set(theme.rawValue, forKey: AppConstants.AppGroup.themeKey)
        }
        WidgetCenter.shared.reloadAllTimelines()

        // Switch app icon to match the theme
        let currentIcon = UIApplication.shared.alternateIconName
        if currentIcon != theme.alternateIconName {
            UIApplication.shared.setAlternateIconName(theme.alternateIconName)
        }
    }
}
