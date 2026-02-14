import Foundation
import SwiftData

/// Orchestrates the daily cycle: fetch prayer times → schedule alarms → sync calendar.
/// This is the single entry point for refreshing all data.
@Observable
@MainActor
final class AppCoordinator {
    private let prayerTimeService: PrayerTimeService
    private let alarmService: AlarmSchedulingService
    private let calendarService: CalendarService
    private let locationService: LocationService
    private let cloudContext: ModelContext
    private let localContext: ModelContext

    var isRefreshing = false
    var lastError: Error?

    init(
        prayerTimeService: PrayerTimeService,
        alarmService: AlarmSchedulingService,
        calendarService: CalendarService,
        locationService: LocationService,
        cloudContext: ModelContext,
        localContext: ModelContext
    ) {
        self.prayerTimeService = prayerTimeService
        self.alarmService = alarmService
        self.calendarService = calendarService
        self.locationService = locationService
        self.cloudContext = cloudContext
        self.localContext = localContext
    }

    // MARK: - Main Refresh Cycle

    /// Full refresh: location → fetch times → schedule alarms → sync calendar.
    /// Called on app launch (if stale), midnight, location change, and pull-to-refresh.
    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil

        do {
            // 1. Get current location
            let location = try await locationService.getCurrentLocation()
            let timezone = TimeZone.current

            // 2. Get or create preferences
            let preferences = try getOrCreatePreferences()
            preferences.latitude = location.coordinate.latitude
            preferences.longitude = location.coordinate.longitude
            preferences.lastRefreshDate = Date()

            // 3. Fetch prayer times for today
            let today = Date()
            let timezoneID = timezone.identifier
            try await prayerTimeService.fetchMonth(
                year: Calendar.current.component(.year, from: today),
                month: Calendar.current.component(.month, from: today),
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                method: preferences.calculationMethod,
                school: preferences.school,
                timezone: timezoneID
            )

            // Always fetch next month too so we have 30+ days of data for calendar sync
            let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: today) ?? today
            try await prayerTimeService.fetchMonth(
                year: Calendar.current.component(.year, from: nextMonth),
                month: Calendar.current.component(.month, from: nextMonth),
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                method: preferences.calculationMethod,
                school: preferences.school,
                timezone: timezoneID
            )

            // 4. Get today's prayer times and schedule alarms
            if let todayTimes = prayerTimeService.getCachedTimes(for: today) {
                let configs = try getOrCreateAlarmConfigs()
                try await alarmService.reconcileAlarms(prayerTimes: todayTimes, configs: configs)

                // 5. Sync to calendar if enabled and access is granted — 30 days ahead
                let hasCalendarAccess: Bool
                if preferences.calendarSyncEnabled, calendarService.hasAccess {
                    hasCalendarAccess = true
                } else if preferences.calendarSyncEnabled, !calendarService.hasAccess {
                    hasCalendarAccess = (try? await calendarService.requestAccess()) ?? false
                } else {
                    hasCalendarAccess = false
                }

                if hasCalendarAccess {
                    if preferences.calendarSyncAhead {
                        // Sync the next 30 days of prayer times to calendar
                        var upcomingDays: [DailyPrayerTimes] = []
                        for dayOffset in 0..<30 {
                            if let futureDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: today),
                               let cached = prayerTimeService.getCachedTimes(for: futureDate) {
                                upcomingDays.append(cached)
                            }
                        }
                        try await calendarService.syncPrayerEvents(for: upcomingDays)
                    } else {
                        // Just sync today
                        try await calendarService.syncPrayerEvents(for: todayTimes)
                    }
                }
            }

            // 6. Schedule tomorrow's Fajr for overnight coverage.
            //    Only schedule if today's Fajr has already passed (avoid double-scheduling).
            //    Respects usesSunriseOffset: if enabled, alarm is relative to tomorrow's sunrise.
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
            let cachedToday = prayerTimeService.getCachedTimes(for: today)
            let todayFajrPassed = cachedToday?.fajr.map { $0 < Date() } ?? true
            if todayFajrPassed,
               let tomorrowTimes = prayerTimeService.getCachedTimes(for: tomorrow),
               let fajrConfig = try getOrCreateAlarmConfigs().first(where: { $0.prayerName == Prayer.fajr.rawValue }),
               fajrConfig.isEnabled,
               let fajrTime = tomorrowTimes.fajr {

                // Use sunrise as reference if the user enabled "Relative to Sunrise"
                let referenceTime: Date
                if fajrConfig.usesSunriseOffset, let sunrise = tomorrowTimes.sunrise {
                    referenceTime = sunrise
                } else {
                    referenceTime = fajrTime
                }

                let scheduledTime = referenceTime.addingTimeInterval(TimeInterval(fajrConfig.offsetMinutes * 60))

                if scheduledTime > Date() {
                    try await alarmService.cancelAlarm(for: .fajr)
                    try await alarmService.scheduleAlarm(for: .fajr, at: scheduledTime, config: fajrConfig)
                }
            }

            try cloudContext.save()

        } catch {
            lastError = error
        }

        isRefreshing = false
    }

    /// Lightweight check: should we refresh? Called on foreground return.
    func refreshIfNeeded() async {
        let preferences = try? getOrCreatePreferences()
        guard let lastRefresh = preferences?.lastRefreshDate else {
            await refreshAll()
            return
        }

        // Refresh if the last refresh was not today
        if !Calendar.current.isDateInToday(lastRefresh) {
            await refreshAll()
        }
    }

    // MARK: - Data Helpers

    private func getOrCreatePreferences() throws -> UserPreferences {
        let descriptor = FetchDescriptor<UserPreferences>()
        let existing = try cloudContext.fetch(descriptor)
        if let prefs = existing.first {
            return prefs
        }
        let prefs = UserPreferences()
        cloudContext.insert(prefs)
        return prefs
    }

    func getOrCreateAlarmConfigs() throws -> [PrayerAlarmConfig] {
        let descriptor = FetchDescriptor<PrayerAlarmConfig>()
        var configs = try cloudContext.fetch(descriptor)

        // Ensure we have a config for every prayer
        for prayer in Prayer.allCases {
            if !configs.contains(where: { $0.prayerName == prayer.rawValue }) {
                let config = PrayerAlarmConfig(prayer: prayer)
                cloudContext.insert(config)
                configs.append(config)
            }
        }

        return configs.sorted { ($0.prayer?.sortOrder ?? 0) < ($1.prayer?.sortOrder ?? 0) }
    }
}
