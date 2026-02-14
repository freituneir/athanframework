import Foundation
import SwiftData
import SwiftUI
import UserNotifications
import AlarmKit

/// Schedules and manages AlarmKit alarms for the five daily prayers.
@Observable
@MainActor
final class AlarmSchedulingService {

    // MARK: - State

    /// Whether the user has granted alarm permission.
    private(set) var isAuthorized = false

    /// The local-only ModelContext for reading / writing `DeviceAlarmState`.
    private let localContext: ModelContext

    /// Device identifier used to scope alarm state records.
    private let deviceID: String

    // MARK: - Init

    init(localContainer: ModelContainer) {
        self.localContext = ModelContext(localContainer)
        self.deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }

    // MARK: - Authorization

    /// Requests AlarmKit authorization from the user.
    /// Returns `true` when authorized.
    @discardableResult
    func requestAuthorization() async throws -> Bool {
        print("[AlarmKit] Requesting authorization...")
        let status = try await AlarmManager.shared.requestAuthorization()
        print("[AlarmKit] Authorization result: \(status)")
        isAuthorized = status == .authorized
        return isAuthorized
    }

    // MARK: - Reconcile (main entry point)

    /// How far in advance (seconds) the Live Activity countdown appears before a prayer.
    static let preAlertWindow: TimeInterval = 30 * 60 // 30 minutes

    /// Cancels outdated alarms and schedules all upcoming prayers.
    /// Each alarm uses Schedule.fixed() + CountdownDuration so the Live Activity
    /// only appears 30 minutes before the prayer, not immediately.
    func reconcileAlarms(
        prayerTimes: DailyPrayerTimes,
        configs: [PrayerAlarmConfig],
        tomorrowFajrTime: Date? = nil
    ) async throws {
        let orderedPrayers = Prayer.allCases // [.fajr, .dhuhr, .asr, .maghrib, .isha]

        for (index, prayer) in orderedPrayers.enumerated() {
            guard let config = configs.first(where: { $0.prayerName == prayer.rawValue }) else {
                continue
            }

            guard config.isEnabled, let baseTime = prayerTimes.time(for: prayer) else {
                try await cancelAlarm(for: prayer)
                continue
            }

            // For Fajr with sunrise offset: compute time relative to sunrise instead of Fajr
            let referenceTime: Date
            if prayer == .fajr, config.usesSunriseOffset, let sunrise = prayerTimes.sunrise {
                referenceTime = sunrise
            } else {
                referenceTime = baseTime
            }

            let scheduledTime = referenceTime.addingTimeInterval(TimeInterval(config.offsetMinutes * 60))

            guard scheduledTime > Date.now else {
                continue
            }

            // Compute next prayer info for post-alert countdown
            let nextPrayer: Prayer?
            let nextPrayerTime: Date?
            if index + 1 < orderedPrayers.count {
                let next = orderedPrayers[index + 1]
                nextPrayer = next
                nextPrayerTime = prayerTimes.time(for: next)
            } else {
                // After Isha, next is tomorrow's Fajr
                nextPrayer = .fajr
                nextPrayerTime = tomorrowFajrTime
            }

            try await cancelAlarm(for: prayer)
            try await scheduleAlarm(
                for: prayer,
                at: scheduledTime,
                config: config,
                nextPrayer: nextPrayer,
                nextPrayerTime: nextPrayerTime
            )
        }
    }

    // MARK: - Schedule

    /// Schedules a single AlarmKit alarm for a prayer.
    /// Uses Schedule.fixed() so the alarm fires at the exact prayer time,
    /// plus CountdownDuration with a 30-minute preAlert so the Live Activity
    /// only appears 30 minutes before — not immediately on schedule().
    func scheduleAlarm(
        for prayer: Prayer,
        at time: Date,
        config: PrayerAlarmConfig,
        nextPrayer: Prayer? = nil,
        nextPrayerTime: Date? = nil
    ) async throws {
        print("[AlarmKit] Scheduling alarm for \(prayer.displayName) at \(time)")
        let alarmID = UUID()

        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: "\(prayer.displayName) Prayer"),
            stopButton: .prayerStopButton,
            secondaryButton: .prayerSnoozeButton,
            secondaryButtonBehavior: .custom
        )

        let countdownPresentation = AlarmPresentation.Countdown(
            title: LocalizedStringResource(stringLiteral: "\(prayer.displayName) Prayer")
        )

        let presentation = AlarmPresentation(
            alert: alertPresentation,
            countdown: countdownPresentation
        )

        let tintColor = Color(hex: config.tintColorHex)
        let metadata = PrayerAlarmMetadata(prayer: prayer, fireDate: time, nextPrayer: nextPrayer)

        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: metadata,
            tintColor: tintColor
        )

        // Schedule: fire at the exact prayer time
        let schedule = Alarm.Schedule.fixed(time)

        // preAlert: Live Activity countdown appears this many seconds before the alarm fires.
        // Use 30 minutes, but cap at the actual time remaining if less than 30 min away.
        let secondsUntil = time.timeIntervalSince(.now)
        let preAlertSeconds = min(Self.preAlertWindow, max(secondsUntil, 30))

        // postAlert: how long the Live Activity persists after firing.
        //   Ends when the NEXT prayer's pre-alert begins (30 min before next prayer),
        //   so only one Live Activity is visible at a time.
        //   Fallback: 4 hours if next prayer time isn't available.
        let postAlertSeconds: TimeInterval
        if let nextTime = nextPrayerTime, nextTime > time {
            let gapToNext = nextTime.timeIntervalSince(time)
            postAlertSeconds = max(60, gapToNext - Self.preAlertWindow)
        } else {
            postAlertSeconds = 4 * 60 * 60
        }

        let countdownDuration = Alarm.CountdownDuration(
            preAlert: preAlertSeconds,
            postAlert: postAlertSeconds
        )

        let stopIntent = StopPrayerIntent(alarmID: alarmID.uuidString, entityName: prayer.rawValue)
        let secondaryIntent = RepeatPrayerIntent(alarmID: alarmID.uuidString)

        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            stopIntent: stopIntent,
            secondaryIntent: secondaryIntent
        )

        _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)

        persistAlarmID(alarmID, for: prayer)
        print("[AlarmKit] Alarm scheduled for \(prayer.displayName) at \(time) — preAlert: \(Int(preAlertSeconds))s, postAlert: \(Int(postAlertSeconds))s, ID: \(alarmID)")
    }

    // MARK: - Cancel

    /// Cancels the active alarm for a given prayer, if one exists.
    func cancelAlarm(for prayer: Prayer) async throws {
        guard let state = fetchAlarmState(for: prayer), let alarmID = state.alarmID else {
            return
        }

        do {
            try await AlarmManager.shared.stop(id: alarmID)
        } catch {
            print("[AlarmKit] Stop alarm failed (may have already fired): \(error)")
        }

        localContext.delete(state)
        try localContext.save()
    }

    // MARK: - Alarm Updates

    /// Yields alarm state updates from AlarmKit.
    var alarmUpdates: some AsyncSequence<[Alarm], Never> {
        AlarmManager.shared.alarmUpdates
    }

    // MARK: - Custom Reminder Alarms

    /// Schedules an AlarmKit alarm for an "urgent" custom reminder.
    func scheduleCustomReminderAlarm(_ reminder: CustomReminder) async throws {
        guard let time = reminder.scheduledTime, time > Date.now else { return }

        let alarmID = UUID()
        let stateKey = "reminder-\(reminder.id.uuidString)"

        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: reminder.title),
            stopButton: .prayerStopButton,
            secondaryButton: .prayerSnoozeButton,
            secondaryButtonBehavior: .custom
        )

        let countdownPresentation = AlarmPresentation.Countdown(
            title: LocalizedStringResource(stringLiteral: reminder.title)
        )

        let presentation = AlarmPresentation(
            alert: alertPresentation,
            countdown: countdownPresentation
        )

        let metadata = ReminderAlarmMetadata(title: reminder.title, fireDate: time, entityName: stateKey)

        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: metadata,
            tintColor: Color(hex: AppConstants.Defaults.tintColorHex)
        )

        // Schedule: fire at the exact reminder time
        let schedule = Alarm.Schedule.fixed(time)

        // preAlert: Live Activity appears 30 min before (or less if closer than 30 min)
        let secondsUntil = time.timeIntervalSince(.now)
        let preAlertSeconds = min(Self.preAlertWindow, max(secondsUntil, 30))

        // postAlert: 4 hours for reminders (count UP from fire time)
        let countdownDuration = Alarm.CountdownDuration(
            preAlert: preAlertSeconds,
            postAlert: 4 * 60 * 60
        )

        let stopIntent = StopPrayerIntent(alarmID: alarmID.uuidString, entityName: stateKey)
        let secondaryIntent = RepeatPrayerIntent(alarmID: alarmID.uuidString)

        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            stopIntent: stopIntent,
            secondaryIntent: secondaryIntent
        )

        _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)

        persistAlarmID(alarmID, forKey: stateKey)
        print("[AlarmKit] Urgent reminder alarm scheduled: \(reminder.title) at \(time) — preAlert: \(Int(preAlertSeconds))s, ID: \(alarmID)")
    }

    /// Cancels the AlarmKit alarm for a custom reminder, if one exists.
    func cancelCustomReminderAlarm(reminderID: UUID) async throws {
        let stateKey = "reminder-\(reminderID.uuidString)"
        guard let state = fetchAlarmState(forKey: stateKey), let alarmID = state.alarmID else {
            return
        }

        do {
            try await AlarmManager.shared.stop(id: alarmID)
        } catch {
            print("[AlarmKit] Stop reminder alarm failed (may have already fired): \(error)")
        }

        localContext.delete(state)
        try localContext.save()
        print("[AlarmKit] Cancelled urgent reminder alarm for \(reminderID)")
    }

    // MARK: - Private helpers

    private func fetchAlarmState(for prayer: Prayer) -> DeviceAlarmState? {
        return fetchAlarmState(forKey: prayer.rawValue)
    }

    private func fetchAlarmState(forKey key: String) -> DeviceAlarmState? {
        let device = deviceID
        let descriptor = FetchDescriptor<DeviceAlarmState>(
            predicate: #Predicate { $0.prayerName == key && $0.deviceID == device }
        )
        return try? localContext.fetch(descriptor).first
    }

    private func persistAlarmID(_ id: UUID, for prayer: Prayer) {
        persistAlarmID(id, forKey: prayer.rawValue)
    }

    private func persistAlarmID(_ id: UUID, forKey key: String) {
        if let existing = fetchAlarmState(forKey: key) {
            existing.alarmID = id
            existing.lastScheduled = Date()
        } else {
            let state = DeviceAlarmState(
                prayerName: key,
                alarmID: id,
                deviceID: deviceID
            )
            localContext.insert(state)
        }
        try? localContext.save()
    }
}
