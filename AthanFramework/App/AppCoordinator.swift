import Foundation
import SwiftData
import WidgetKit

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
            // 0. Clean up stale alarm records (>24h old)
            alarmService.cleanupStaleAlarms()

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
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
            let tomorrowTimes = prayerTimeService.getCachedTimes(for: tomorrow)

            if let todayTimes = prayerTimeService.getCachedTimes(for: today) {
                let configs = try getOrCreateAlarmConfigs()
                try await alarmService.reconcileAlarms(
                    prayerTimes: todayTimes,
                    configs: configs,
                    tomorrowFajrTime: tomorrowTimes?.fajr,
                    athanSound: preferences.selectedAthanSound
                )

                // Reconcile standalone "Pray Now" LAs — independent of AlarmKit
                let completedPrayers = readCompletedPrayers()
                alarmService.reconcilePrayNowActivities(
                    prayerTimes: todayTimes,
                    completedPrayers: completedPrayers
                )

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

            // 6. Update app badge, home screen widget, theme, and reminder delay
            let cachedTodayForBadge = prayerTimeService.getCachedTimes(for: today)
            BadgeService.updateBadge(cloudContext: cloudContext, todayTimes: cachedTodayForBadge)
            writePrayerDataToAppGroup(todayTimes: cachedTodayForBadge)
            writeThemeToAppGroup(preferences.selectedTheme)
            writeReminderDelayToAppGroup(preferences.reminderDelayMinutes)

            // 7. Schedule tomorrow's Fajr for overnight coverage.
            try await scheduleTomorrowFajrIfNeeded(
                todayTimes: cachedTodayForBadge,
                tomorrowTimes: tomorrowTimes
            )

            try cloudContext.save()

        } catch is CancellationError {
            // Ignore task cancellations (e.g. pull-to-refresh interrupted)
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Ignore URLSession cancellations (e.g. pull-to-refresh interrupted)
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
        } else {
            // Same day — re-reconcile alarms (cancel passed, schedule upcoming)
            await reconcileAlarmsFromCache()
        }
    }

    /// Re-reconcile alarms using cached prayer times — no network call.
    /// Called on foreground return (same day) to ensure alarms are current.
    private func reconcileAlarmsFromCache() async {
        let today = Date()
        guard let todayTimes = prayerTimeService.getCachedTimes(for: today) else { return }

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        let tomorrowTimes = prayerTimeService.getCachedTimes(for: tomorrow)

        do {
            let configs = try getOrCreateAlarmConfigs()
            let preferences = try getOrCreatePreferences()
            try await alarmService.reconcileAlarms(
                prayerTimes: todayTimes,
                configs: configs,
                tomorrowFajrTime: tomorrowTimes?.fajr,
                athanSound: preferences.selectedAthanSound
            )

            // Reconcile standalone "Pray Now" LAs
            let completedPrayers = readCompletedPrayers()
            alarmService.reconcilePrayNowActivities(
                prayerTimes: todayTimes,
                completedPrayers: completedPrayers
            )

            // Schedule tomorrow's Fajr if today's has passed — ensures overnight coverage
            // even when refreshAll() ran before Fajr earlier in the day.
            try await scheduleTomorrowFajrIfNeeded(
                todayTimes: todayTimes,
                tomorrowTimes: tomorrowTimes
            )
        } catch {
            print("[AppCoordinator] reconcileAlarmsFromCache failed: \(error)")
        }
    }

    // MARK: - Tomorrow's Fajr (Overnight Coverage)

    /// Schedules tomorrow's Fajr alarm if today's Fajr has already passed.
    /// Called from both refreshAll() and reconcileAlarmsFromCache() so that
    /// tomorrow's Fajr is always scheduled once today's passes — even if
    /// refreshAll() ran before Fajr earlier in the day.
    private func scheduleTomorrowFajrIfNeeded(
        todayTimes: DailyPrayerTimes?,
        tomorrowTimes: DailyPrayerTimes?
    ) async throws {
        let todayFajrPassed = todayTimes?.fajr.map { $0 < Date() } ?? true

        // Don't schedule if Fajr already has an active alarm in AlarmKit
        if let existingID = alarmService.fetchAlarmState(for: .fajr)?.alarmID,
           alarmService.activeAlarmIDs.contains(existingID) {
            return
        }

        guard todayFajrPassed,
              let tomorrowTimesForFajr = tomorrowTimes,
              let fajrConfig = try getOrCreateAlarmConfigs().first(where: { $0.prayerName == Prayer.fajr.rawValue }),
              fajrConfig.isEnabled,
              let fajrTime = tomorrowTimesForFajr.fajr else {
            return
        }

        // Use sunrise as reference if the user enabled "Relative to Sunrise"
        let referenceTime: Date
        if fajrConfig.usesSunriseOffset, let sunrise = tomorrowTimesForFajr.sunrise {
            referenceTime = sunrise
        } else {
            referenceTime = fajrTime
        }

        let scheduledTime = referenceTime.addingTimeInterval(TimeInterval(fajrConfig.offsetMinutes * 60))

        guard scheduledTime > Date() else { return }

        let preferences = try getOrCreatePreferences()
        // Explicit cancel — this path bypasses reconcileAlarms() which normally handles per-prayer cleanup
        try await alarmService.cancelAlarm(for: .fajr)
        try await alarmService.scheduleAlarm(
            for: .fajr,
            at: scheduledTime,
            rawPrayerTime: fajrTime,
            config: fajrConfig,
            nextPrayer: .dhuhr,
            nextPrayerTime: tomorrowTimesForFajr.dhuhr,
            athanSound: preferences.selectedAthanSound
        )
    }

    // MARK: - Pray Now Activities

    /// Ends the standalone "Pray Now" LA for a prayer — called when marking done in app.
    func endPrayNowActivity(for prayer: Prayer) {
        alarmService.endPrayNowActivity(for: prayer)
    }

    /// Reads today's completed prayers from App Group UserDefaults.
    func readCompletedPrayers() -> Set<String> {
        guard let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) else { return [] }
        let completed = suite.dictionary(forKey: AppConstants.AppGroup.completedKey) as? [String: Double] ?? [:]
        let todayStart = Calendar.current.startOfDay(for: Date())
        var result: Set<String> = []
        for (key, timestamp) in completed {
            let date = Date(timeIntervalSince1970: timestamp)
            if date >= todayStart {
                result.insert(key)
            }
        }
        return result
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

    /// Cancels the active alarm for a prayer — called when marking done in the app.
    func cancelAlarm(for prayer: Prayer) async throws {
        try await alarmService.cancelAlarm(for: prayer)
    }

    /// Cancels the reminder alarm for a prayer — called when marking done.
    func cancelReminderAlarm(for prayer: Prayer) async throws {
        try await alarmService.cancelReminderAlarm(for: prayer)
    }

    /// Whether AlarmKit currently has an active alarm for this prayer.
    func hasActiveAlarm(for prayer: Prayer) -> Bool {
        guard let existingID = alarmService.fetchAlarmState(for: prayer)?.alarmID else { return false }
        return alarmService.activeAlarmIDs.contains(existingID)
    }

    /// Whether a followup alarm is active for this prayer.
    func hasActiveFollowup(for prayer: Prayer) -> Bool {
        alarmService.hasActiveFollowup(for: prayer)
    }

    /// Cancels the followup alarm for a prayer — called when marking done.
    func cancelFollowupAlarm(for prayer: Prayer) {
        alarmService.cancelFollowupAlarm(for: prayer)
    }

    /// Silently schedules a recovery Live Activity for a missed prayer.
    /// Called on foreground return when the alarm was dismissed but prayer isn't marked done.
    func recoverMissedAlarm(for prayer: Prayer, originalFireDate: Date) async throws {
        let configs = try getOrCreateAlarmConfigs()
        guard let config = configs.first(where: { $0.prayerName == prayer.rawValue }) else { return }

        let today = Date()
        let todayTimes = prayerTimeService.getCachedTimes(for: today)

        // Determine next prayer info for the LA metadata
        let orderedPrayers = Prayer.allCases
        let nextPrayer: Prayer?
        let nextPrayerTime: Date?
        if let idx = orderedPrayers.firstIndex(of: prayer), idx + 1 < orderedPrayers.count {
            let next = orderedPrayers[idx + 1]
            nextPrayer = next
            nextPrayerTime = todayTimes?.time(for: next)
        } else {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
            let tomorrowTimes = prayerTimeService.getCachedTimes(for: tomorrow)
            nextPrayer = .fajr
            nextPrayerTime = tomorrowTimes?.fajr
        }

        let preferences = try getOrCreatePreferences()

        try await alarmService.scheduleRecoveryAlarm(
            for: prayer,
            originalFireDate: originalFireDate,
            config: config,
            nextPrayer: nextPrayer,
            nextPrayerTime: nextPrayerTime,
            athanSound: preferences.selectedAthanSound
        )
    }

    /// Writes today's prayer times + completions to App Group UserDefaults for the home screen widget.
    func writePrayerDataToAppGroup(todayTimes: DailyPrayerTimes?) {
        guard let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) else { return }

        var timesDict: [String: Double] = [:]
        if let times = todayTimes {
            for prayer in Prayer.allCases {
                if let t = times.time(for: prayer) {
                    timesDict[prayer.rawValue] = t.timeIntervalSince1970
                }
            }
            if let sunrise = times.sunrise {
                timesDict["sunrise"] = sunrise.timeIntervalSince1970
            }
        }
        suite.set(timesDict, forKey: AppConstants.AppGroup.prayerTimesKey)

        // Reload widget timelines
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Writes selected theme to App Group so widgets and LAs can read it.
    func writeThemeToAppGroup(_ theme: ColorTheme) {
        guard let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) else { return }
        suite.set(theme.rawValue, forKey: AppConstants.AppGroup.themeKey)
    }

    /// Writes reminder delay to App Group so intents can read it for push-back.
    func writeReminderDelayToAppGroup(_ minutes: Int) {
        guard let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) else { return }
        suite.set(minutes, forKey: AppConstants.AppGroup.reminderDelayKey)
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
