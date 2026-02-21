import Foundation
import SwiftData

/// ViewModel for the main prayer times screen.
/// Shows today's 5 prayer times with their alarm status.
@Observable
@MainActor
final class PrayerTimesViewModel {
    private let coordinator: AppCoordinator
    private let cloudContext: ModelContext
    private var countdownTimer: Timer?

    var todayTimes: DailyPrayerTimes?
    var tomorrowTimes: DailyPrayerTimes?
    var yesterdayTimes: DailyPrayerTimes?
    var alarmConfigs: [PrayerAlarmConfig] = []
    var isLoading = false
    var errorMessage: String?
    var countdownToNext: String?
    var countdownFormatted: String?
    var progressToNextPrayer: Double = 0
    var completions: [PrayerCompletion] = []
    /// Tracks which prayer we've already recovered for this foreground session,
    /// to avoid duplicate scheduling on repeated scenePhase transitions.
    private var recoveredPrayers: Set<String> = []

    init(coordinator: AppCoordinator, cloudContext: ModelContext) {
        self.coordinator = coordinator
        self.cloudContext = cloudContext
    }

    /// Load today's prayer times from SwiftData cache.
    /// Uses a range predicate (start of day to end of day) to avoid timezone mismatch
    /// between the device and the stored prayer times.
    func loadTodayTimes() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let descriptor = FetchDescriptor<DailyPrayerTimes>(
            predicate: #Predicate { $0.date >= startOfDay && $0.date < endOfDay }
        )
        todayTimes = try? cloudContext.fetch(descriptor).first

        // Also load tomorrow's times for Fajr countdown when all today's prayers have passed
        let startOfTomorrow = endOfDay
        let endOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfTomorrow) ?? startOfTomorrow
        let tomorrowDescriptor = FetchDescriptor<DailyPrayerTimes>(
            predicate: #Predicate { $0.date >= startOfTomorrow && $0.date < endOfTomorrow }
        )
        tomorrowTimes = try? cloudContext.fetch(tomorrowDescriptor).first

        // Load yesterday's times for progress bar (need yesterday's Isha when before today's Fajr)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
        let yesterdayDescriptor = FetchDescriptor<DailyPrayerTimes>(
            predicate: #Predicate { $0.date >= startOfYesterday && $0.date < startOfDay }
        )
        yesterdayTimes = try? cloudContext.fetch(yesterdayDescriptor).first

        loadAlarmConfigs()
        loadCompletions()
        startCountdownTimer()
    }

    /// Load alarm configs for all prayers.
    func loadAlarmConfigs() {
        alarmConfigs = (try? coordinator.getOrCreateAlarmConfigs()) ?? []
    }

    /// Pull-to-refresh: triggers a full coordinator refresh.
    func refresh() async {
        isLoading = true
        errorMessage = nil
        await coordinator.refreshAll()
        if let error = coordinator.lastError {
            errorMessage = error.localizedDescription
        }
        loadTodayTimes()
        isLoading = false
    }

    /// Lightweight foreground-return check: re-fetch data if stale, re-reconcile alarms.
    func refreshIfNeeded() async {
        await coordinator.refreshIfNeeded()
        loadTodayTimes()
    }

    /// Toggle alarm on/off for a specific prayer.
    /// Immediately cancels or schedules the AlarmKit alarm.
    func toggleAlarm(for prayer: Prayer) {
        guard let config = alarmConfigs.first(where: { $0.prayerName == prayer.rawValue }) else { return }
        config.isEnabled.toggle()
        try? cloudContext.save()

        Task {
            if config.isEnabled {
                // Re-reconcile to schedule the newly enabled alarm
                await coordinator.refreshIfNeeded()
            } else {
                // Immediately cancel the alarm in AlarmKit
                try? await coordinator.cancelAlarm(for: prayer)
            }
        }
    }

    /// Load today's completion records, creating missing ones.
    /// Also syncs any completions written by the Live Activity's MarkDoneIntent.
    func loadCompletions() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let descriptor = FetchDescriptor<PrayerCompletion>(
            predicate: #Predicate { $0.date >= startOfDay && $0.date < endOfDay }
        )
        var existing = (try? cloudContext.fetch(descriptor)) ?? []

        // Ensure we have a record for every prayer today
        for prayer in Prayer.allCases {
            if !existing.contains(where: { $0.prayerName == prayer.rawValue }) {
                let completion = PrayerCompletion(date: Date(), prayer: prayer)
                cloudContext.insert(completion)
                existing.append(completion)
            }
        }

        // Sync completions from Live Activity "Done" button via shared UserDefaults
        syncSharedCompletions(into: &existing)

        try? cloudContext.save()
        completions = existing
    }

    /// Reads prayer completions written by MarkDoneIntent in the widget extension
    /// and marks corresponding PrayerCompletion records as done.
    /// Only removes STALE entries (from previous days). Today's entries are kept
    /// so reconcilePrayNowActivities() can see them.
    private func syncSharedCompletions(into completions: inout [PrayerCompletion]) {
        guard let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) else { return }
        guard var completed = suite.dictionary(forKey: AppConstants.AppGroup.completedKey) as? [String: Double] else { return }

        let todayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let todayEnd = todayStart + 86400
        var staleKeys: [String] = []

        for (key, timestamp) in completed {
            guard timestamp >= todayStart && timestamp < todayEnd else {
                staleKeys.append(key)
                continue
            }

            // Sync today's widget-side completions into SwiftData
            if let prayer = Prayer(rawValue: key),
               let record = completions.first(where: { $0.prayerName == prayer.rawValue }),
               !record.isCompleted {
                record.isCompleted = true
                record.completedAt = Date(timeIntervalSince1970: timestamp)
            }
        }

        // Only remove stale entries from previous days — keep today's
        for key in staleKeys {
            completed.removeValue(forKey: key)
        }
        suite.set(completed, forKey: AppConstants.AppGroup.completedKey)
    }

    /// Toggle completion state for a prayer.
    /// When marking complete, also cancels the Live Activity / alarm so they share state.
    func toggleCompletion(for prayer: Prayer) {
        guard let completion = completions.first(where: { $0.prayerName == prayer.rawValue }) else { return }
        completion.isCompleted.toggle()
        completion.completedAt = completion.isCompleted ? Date() : nil
        try? cloudContext.save()

        // Sync to App Group so reconcilePrayNowActivities() sees the completion
        writeCompletionToAppGroup(prayer: prayer, isCompleted: completion.isCompleted)

        // Update badge count
        BadgeService.updateBadge(cloudContext: cloudContext, todayTimes: todayTimes)

        // Dismiss the Live Activity and cancel all related alarms when marking done
        if completion.isCompleted {
            coordinator.endPrayNowActivity(for: prayer)
            Task {
                try? await coordinator.cancelAlarm(for: prayer)
                try? await coordinator.cancelReminderAlarm(for: prayer)
                coordinator.cancelFollowupAlarm(for: prayer)
            }
        }
    }

    /// Writes a prayer's completion state to App Group so the widget and reconcile can see it.
    private func writeCompletionToAppGroup(prayer: Prayer, isCompleted: Bool) {
        guard let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) else { return }
        var completed = suite.dictionary(forKey: AppConstants.AppGroup.completedKey) as? [String: Double] ?? [:]
        if isCompleted {
            completed[prayer.rawValue] = Date().timeIntervalSince1970
        } else {
            completed.removeValue(forKey: prayer.rawValue)
        }
        suite.set(completed, forKey: AppConstants.AppGroup.completedKey)
    }

    /// Whether a prayer is completed today.
    func isCompleted(_ prayer: Prayer) -> Bool {
        completions.first(where: { $0.prayerName == prayer.rawValue })?.isCompleted ?? false
    }

    /// Returns the time string for display, or "--:--" if not available.
    func timeString(for prayer: Prayer) -> String {
        guard let time = todayTimes?.time(for: prayer) else { return "--:--" }
        return DateFormatter.prayerTime.string(from: time)
    }

    /// Returns true if this prayer time has already passed today.
    func hasPassed(_ prayer: Prayer) -> Bool {
        guard let time = todayTimes?.time(for: prayer) else { return false }
        return time.isPast
    }

    // MARK: - Sunrise Display

    /// Formatted sunrise time for display, e.g., "6:15 AM".
    var sunriseTimeString: String {
        guard let sunrise = todayTimes?.sunrise else { return "--:--" }
        return DateFormatter.prayerTime.string(from: sunrise)
    }

    /// Whether sunrise has already passed today.
    var sunriseHasPassed: Bool {
        guard let sunrise = todayTimes?.sunrise else { return false }
        return sunrise.isPast
    }

    /// Returns a short description of the alarm offset for a prayer, or nil if at prayer time.
    /// e.g., "30 min before sunrise" or "5 min after"
    func offsetDescription(for prayer: Prayer) -> String? {
        guard let config = alarmConfigs.first(where: { $0.prayerName == prayer.rawValue }),
              config.isEnabled,
              config.offsetMinutes != 0 else {
            return nil
        }

        let abs = abs(config.offsetMinutes)
        let direction = config.offsetMinutes < 0 ? "before" : "after"

        if prayer == .fajr && config.usesSunriseOffset {
            return "\(abs) min \(direction) sunrise"
        } else {
            return "\(abs) min \(direction)"
        }
    }

    /// Returns the next upcoming prayer, or nil if all have passed.
    var nextPrayer: Prayer? {
        for prayer in Prayer.allCases {
            if !hasPassed(prayer) {
                return prayer
            }
        }
        return nil
    }

    /// Returns the most recently passed prayer today, or nil if none have passed (before Fajr).
    var mostRecentlyPassedPrayer: Prayer? {
        Prayer.allCases.last(where: { hasPassed($0) })
    }

    /// Hijri date for display.
    var hijriDate: String {
        todayTimes?.hijriDate ?? ""
    }

    /// Tomorrow's Fajr time formatted for display.
    var tomorrowFajrTimeString: String {
        guard let fajr = tomorrowTimes?.fajr else { return "--:--" }
        return DateFormatter.prayerTime.string(from: fajr)
    }

    // MARK: - Countdown Timer

    /// Starts a timer that updates the countdown string every second.
    private func startCountdownTimer() {
        countdownTimer?.invalidate()
        updateCountdown()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCountdown()
            }
        }
    }

    /// Updates the countdown string and progress to the next prayer.
    private func updateCountdown() {
        // If all today's prayers have passed, count down to tomorrow's Fajr
        let time: Date
        if let next = nextPrayer, let t = todayTimes?.time(for: next) {
            time = t
        } else if let fajrTime = tomorrowTimes?.fajr {
            time = fajrTime
        } else {
            countdownToNext = nil
            countdownFormatted = nil
            progressToNextPrayer = 0
            return
        }

        let interval = time.timeIntervalSince(Date())
        guard interval > 0 else {
            countdownToNext = nil
            countdownFormatted = nil
            progressToNextPrayer = 1
            return
        }

        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        // Legacy format
        if hours > 0 {
            countdownToNext = "\(hours)h \(minutes)m remaining"
        } else {
            countdownToNext = "\(minutes)m remaining"
        }

        // Compact format for the new UI
        if hours > 0 {
            countdownFormatted = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            countdownFormatted = String(format: "%d:%02d", minutes, seconds)
        }

        // Progress: fraction of time elapsed between most recent prayer and next prayer.
        // e.g. if Asr was at 3:30 PM, Maghrib at 5:30 PM, and it's 4:30 PM → progress = 50%.
        let prevTime: Date
        if let prev = Prayer.allCases.last(where: { hasPassed($0) }),
           let pt = todayTimes?.time(for: prev) {
            // Most recent prayer that already came in today
            prevTime = pt
        } else if let yesterdayIsha = yesterdayTimes?.isha {
            // Before Fajr: use yesterday's Isha as the anchor
            prevTime = yesterdayIsha
        } else {
            // No data — use midnight as fallback
            prevTime = Calendar.current.startOfDay(for: Date())
        }
        let totalInterval = time.timeIntervalSince(prevTime)
        let elapsed = Date().timeIntervalSince(prevTime)
        progressToNextPrayer = totalInterval > 0 ? min(max(elapsed / totalInterval, 0), 1) : 0
    }

    // MARK: - Silent Recovery

    /// On foreground return, checks ALL recently-fired alarms for uncompleted prayers.
    /// For each one, silently schedules a recovery Live Activity so "Pray Now" + Done
    /// reappears on the lock screen. Supports multiple prayers simultaneously.
    func recoverMissedAlarmIfNeeded() async {
        guard let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) else { return }

        // Read the per-prayer fired alarms dictionary
        let firedAlarms = suite.dictionary(forKey: AppConstants.AppGroup.firedAlarmsKey) as? [String: Double] ?? [:]
        // Also check legacy single-key format for backward compatibility
        var allFired = firedAlarms
        if let legacyName = suite.string(forKey: AppConstants.AppGroup.lastFiredAlarmKey) {
            let legacyTime = suite.double(forKey: AppConstants.AppGroup.lastFiredAlarmTimeKey)
            if legacyTime > 0, allFired[legacyName] == nil {
                allFired[legacyName] = legacyTime
            }
        }

        for (prayerName, fireTimestamp) in allFired {
            guard let prayer = Prayer(rawValue: prayerName) else { continue }

            let fireDate = Date(timeIntervalSince1970: fireTimestamp)
            let elapsed = Date().timeIntervalSince(fireDate)

            // Only recover if: fire date passed, within 4 hours, prayer not completed
            guard elapsed > 0, elapsed < 4 * 3600, !isCompleted(prayer) else { continue }

            // Don't re-schedule if already recovered this session
            guard !recoveredPrayers.contains(prayerName) else { continue }

            // Don't re-schedule if there's already an active alarm or followup
            guard !coordinator.hasActiveAlarm(for: prayer),
                  !coordinator.hasActiveFollowup(for: prayer) else { continue }

            do {
                try await coordinator.recoverMissedAlarm(for: prayer, originalFireDate: fireDate)
                recoveredPrayers.insert(prayerName)
                // Remove this entry from the dict so we don't re-recover on next foreground
                var updated = suite.dictionary(forKey: AppConstants.AppGroup.firedAlarmsKey) as? [String: Double] ?? [:]
                updated.removeValue(forKey: prayerName)
                suite.set(updated, forKey: AppConstants.AppGroup.firedAlarmsKey)
                print("[PrayerTimesVM] Recovery alarm scheduled for \(prayer.displayName)")
            } catch {
                print("[PrayerTimesVM] Recovery alarm failed for \(prayer.displayName): \(error)")
            }
        }
    }
}
