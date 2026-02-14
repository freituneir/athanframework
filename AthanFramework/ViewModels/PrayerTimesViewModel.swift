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

    /// Toggle alarm on/off for a specific prayer.
    func toggleAlarm(for prayer: Prayer) {
        guard let config = alarmConfigs.first(where: { $0.prayerName == prayer.rawValue }) else { return }
        config.isEnabled.toggle()
        try? cloudContext.save()
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
