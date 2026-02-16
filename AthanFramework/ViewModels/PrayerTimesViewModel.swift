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
    var alarmConfigs: [PrayerAlarmConfig] = []
    var isLoading = false
    var errorMessage: String?
    var countdownToNext: String?
    var completions: [PrayerCompletion] = []

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
    private func syncSharedCompletions(into completions: inout [PrayerCompletion]) {
        guard let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) else { return }
        guard var completed = suite.dictionary(forKey: AppConstants.AppGroup.completedKey) as? [String: Double] else { return }

        var processed: [String] = []
        let todayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let todayEnd = todayStart + 86400

        for (key, timestamp) in completed {
            // Only process today's completions
            guard timestamp >= todayStart && timestamp < todayEnd else {
                // Remove stale entries from previous days
                processed.append(key)
                continue
            }

            // Check if this is a prayer key
            if let prayer = Prayer(rawValue: key),
               let record = completions.first(where: { $0.prayerName == prayer.rawValue }),
               !record.isCompleted {
                record.isCompleted = true
                record.completedAt = Date(timeIntervalSince1970: timestamp)
            }

            processed.append(key)
        }

        // Remove processed entries
        for key in processed {
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

        // Dismiss the Live Activity when marking done in the app
        if completion.isCompleted {
            Task {
                try? await coordinator.cancelAlarm(for: prayer)
            }
        }
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

    /// Hijri date for display.
    var hijriDate: String {
        todayTimes?.hijriDate ?? ""
    }

    // MARK: - Countdown Timer

    /// Starts a timer that updates the countdown string every second.
    private func startCountdownTimer() {
        countdownTimer?.invalidate()
        updateCountdown()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCountdown()
            }
        }
    }

    /// Updates the countdown string to the next prayer.
    private func updateCountdown() {
        guard let next = nextPrayer,
              let time = todayTimes?.time(for: next) else {
            countdownToNext = nil
            return
        }

        let interval = time.timeIntervalSince(Date())
        guard interval > 0 else {
            countdownToNext = nil
            return
        }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 0 {
            countdownToNext = "\(hours)h \(minutes)m remaining"
        } else {
            countdownToNext = "\(minutes)m remaining"
        }
    }
}
