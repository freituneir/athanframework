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

    /// UUIDs of alarms currently known to AlarmKit — kept in sync via `observeAlarms()`.
    private(set) var activeAlarmIDs: Set<UUID> = []

    /// The local-only ModelContext for reading / writing `DeviceAlarmState`.
    private let localContext: ModelContext

    /// Device identifier used to scope alarm state records.
    private let deviceID: String

    // MARK: - Init

    init(localContainer: ModelContainer) {
        self.localContext = ModelContext(localContainer)
        self.deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        observeAlarms()
    }

    // MARK: - Authorization (Apple sample pattern)

    /// Checks current authorization state before requesting.
    /// Returns `true` when authorized.
    @discardableResult
    func requestAuthorization() async -> Bool {
        // DEBUG: verbose auth logging
        DebugLog.shared.log("Auth: current state = \(AlarmManager.shared.authorizationState)")
        switch AlarmManager.shared.authorizationState {
        case .notDetermined:
            do {
                let state = try await AlarmManager.shared.requestAuthorization()
                isAuthorized = state == .authorized
                DebugLog.shared.log("Auth: requested → \(state), isAuthorized=\(isAuthorized)")
                return isAuthorized
            } catch {
                DebugLog.shared.error("Auth: requestAuthorization threw: \(error)")
                return false
            }
        case .denied:
            DebugLog.shared.error("Auth: denied")
            isAuthorized = false
            return false
        case .authorized:
            DebugLog.shared.log("Auth: already authorized")
            isAuthorized = true
            return true
        @unknown default:
            DebugLog.shared.error("Auth: unknown state")
            return false
        }
    }

    // MARK: - Alarm Observation (Apple sample pattern)

    /// Starts an async loop that keeps `activeAlarmIDs` in sync with AlarmKit.
    /// Called once from init() — mirrors Apple's `observeAlarms()`.
    private func observeAlarms() {
        Task {
            for await incomingAlarms in AlarmManager.shared.alarmUpdates {
                await updateAlarmState(with: incomingAlarms)
            }
        }
    }

    /// Fetches the current snapshot of all alarms from AlarmKit.
    /// Called at startup and before reconcile to ensure local state matches reality.
    func fetchAlarms() {
        // DEBUG: verbose fetch logging
        do {
            let remoteAlarms = try AlarmManager.shared.alarms
            DebugLog.shared.log("fetchAlarms: AlarmKit has \(remoteAlarms.count) alarms")
            for alarm in remoteAlarms {
                DebugLog.shared.log("  alarm \(alarm.id)")
            }
            Task { await updateAlarmState(with: remoteAlarms) }
        } catch {
            DebugLog.shared.error("fetchAlarms: AlarmKit.alarms threw: \(error)")
        }
    }

    /// Syncs local `DeviceAlarmState` records and `activeAlarmIDs` with AlarmKit's ground truth.
    @MainActor
    private func updateAlarmState(with remoteAlarms: [Alarm]) {
        let incomingIDs = Set(remoteAlarms.map(\.id))

        // Remove DeviceAlarmState records for alarms that AlarmKit no longer knows about
        let device = deviceID
        let descriptor = FetchDescriptor<DeviceAlarmState>(
            predicate: #Predicate { $0.deviceID == device }
        )
        if let allStates = try? localContext.fetch(descriptor) {
            for state in allStates {
                if let alarmID = state.alarmID, !incomingIDs.contains(alarmID) {
                    localContext.delete(state)
                }
            }
            try? localContext.save()
        }

        activeAlarmIDs = incomingIDs
    }

    // MARK: - Reconcile (main entry point)

    /// How far in advance (seconds) the Live Activity countdown appears before a prayer.
    static let preAlertWindow: TimeInterval = 5 * 60 // 5 minutes

    /// Non-destructive reconcile: syncs with AlarmKit first, skips active alarms.
    /// Only schedules alarms that don't already exist in AlarmKit.
    func reconcileAlarms(
        prayerTimes: DailyPrayerTimes,
        configs: [PrayerAlarmConfig],
        tomorrowFajrTime: Date? = nil
    ) async throws {
        // DEBUG: verbose reconcile logging
        DebugLog.shared.log("reconcileAlarms: starting, \(configs.count) configs")

        // Sync local state with AlarmKit before making decisions
        fetchAlarms()

        // Write snooze durations to App Group for widget extension access
        writeSnoozeDurationsToAppGroup(configs)

        let orderedPrayers = Prayer.allCases

        for (index, prayer) in orderedPrayers.enumerated() {
            guard let config = configs.first(where: { $0.prayerName == prayer.rawValue }) else {
                DebugLog.shared.log("reconcile: \(prayer.displayName) — no config, skipping")
                continue
            }

            guard config.isEnabled, let baseTime = prayerTimes.time(for: prayer) else {
                DebugLog.shared.log("reconcile: \(prayer.displayName) — disabled or no time, canceling")
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
                DebugLog.shared.log("reconcile: \(prayer.displayName) — time \(scheduledTime) is past, skipping")
                continue
            }

            // Non-destructive: skip if this prayer already has an active alarm in AlarmKit
            if let existingID = fetchAlarmState(for: prayer)?.alarmID,
               activeAlarmIDs.contains(existingID) {
                DebugLog.shared.log("reconcile: \(prayer.displayName) — already active (ID=\(existingID)), skipping")
                continue
            }

            DebugLog.shared.log("reconcile: \(prayer.displayName) — scheduling for \(scheduledTime)")

            // Compute next prayer info
            let nextPrayer: Prayer?
            let nextPrayerTime: Date?
            if index + 1 < orderedPrayers.count {
                let next = orderedPrayers[index + 1]
                nextPrayer = next
                nextPrayerTime = prayerTimes.time(for: next)
            } else {
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
    /// plus CountdownDuration with a 5-minute preAlert and 24-hour postAlert
    /// (LA stays alive through dismiss; daily cleanup handles stale alarms).
    func scheduleAlarm(
        for prayer: Prayer,
        at time: Date,
        config: PrayerAlarmConfig,
        nextPrayer: Prayer? = nil,
        nextPrayerTime: Date? = nil
    ) async throws {
        // DEBUG: verbose schedule logging
        DebugLog.shared.log("scheduleAlarm: \(prayer.displayName) at \(time), auth=\(isAuthorized)")
        let alarmID = UUID()

        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: "\(prayer.displayName) Prayer"),
            stopButton: .prayerDismissButton,
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
        let metadata = PrayerAlarmMetadata(
            prayer: prayer,
            fireDate: time,
            nextPrayer: nextPrayer,
            snoozeDurationSeconds: config.snoozeDurationSeconds
        )

        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: metadata,
            tintColor: tintColor
        )

        // preAlert: LA countdown appears before alarm, capped at actual time remaining
        let secondsUntil = time.timeIntervalSince(.now)
        let preAlertSeconds = min(Self.preAlertWindow, max(secondsUntil, 30))

        // postAlert: gap to next prayer (minus preAlert window), fallback 4 hours
        let postAlertSeconds: TimeInterval
        if let nextTime = nextPrayerTime, nextTime > time {
            let gapToNext = nextTime.timeIntervalSince(time)
            postAlertSeconds = max(60, gapToNext - Self.preAlertWindow)
        } else {
            postAlertSeconds = 4 * 60 * 60
        }

        // Schedule offset: AlarmKit starts the countdown at the schedule time,
        // then fires the alarm after preAlert elapses. Offset by -preAlert so
        // the countdown starts early and the alarm fires at the intended prayer time.
        let schedule = Alarm.Schedule.fixed(time.addingTimeInterval(-preAlertSeconds))

        DebugLog.shared.log("scheduleAlarm: preAlert=\(Int(preAlertSeconds))s, postAlert=\(Int(postAlertSeconds))s, secondsUntil=\(Int(secondsUntil))s, scheduleStart=\(time.addingTimeInterval(-preAlertSeconds))")

        let countdownDuration = Alarm.CountdownDuration(
            preAlert: preAlertSeconds,
            postAlert: postAlertSeconds
        )

        let stopIntent = DismissPrayerIntent(alarmID: alarmID.uuidString, entityName: prayer.rawValue)
        let secondaryIntent = SnoozePrayerIntent(alarmID: alarmID.uuidString, entityName: prayer.rawValue)

        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            stopIntent: stopIntent,
            secondaryIntent: secondaryIntent
        )

        do {
            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            DebugLog.shared.log("scheduleAlarm: SUCCESS \(prayer.displayName) ID=\(alarmID), preAlert=\(Int(preAlertSeconds))s")
        } catch {
            DebugLog.shared.error("scheduleAlarm: FAILED \(prayer.displayName): \(error)")
            throw error
        }

        persistAlarmID(alarmID, for: prayer, fireDate: time)
    }

    // MARK: - Snooze Alarm (alert-only, no Live Activity)

    /// Schedules a new alert-only alarm for snooze — fires after `snoozeDuration` seconds.
    /// Follows Apple sample's `scheduleAlertOnlyExample()` pattern: no countdownDuration, no LA.
    func scheduleSnoozeAlarm(for prayer: Prayer, snoozeDuration: TimeInterval) async throws {
        let snoozeTime = Date.now.addingTimeInterval(snoozeDuration)
        let snoozeID = UUID()

        let alertContent = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: "\(prayer.displayName) — Snooze"),
            stopButton: .prayerDismissButton,
            secondaryButton: .prayerSnoozeButton,
            secondaryButtonBehavior: .custom
        )

        let attributes = AlarmAttributes<PrayerAlarmMetadata>(
            presentation: AlarmPresentation(alert: alertContent),
            tintColor: Color(hex: AppConstants.Defaults.tintColorHex)
        )

        let stopIntent = DismissPrayerIntent(alarmID: snoozeID.uuidString, entityName: prayer.rawValue)
        let secondaryIntent = SnoozePrayerIntent(alarmID: snoozeID.uuidString, entityName: prayer.rawValue)

        let configuration = AlarmManager.AlarmConfiguration(
            schedule: .fixed(snoozeTime),
            attributes: attributes,
            stopIntent: stopIntent,
            secondaryIntent: secondaryIntent
        )

        do {
            _ = try await AlarmManager.shared.schedule(id: snoozeID, configuration: configuration)
            DebugLog.shared.log("scheduleSnoozeAlarm: SUCCESS \(prayer.displayName) in \(Int(snoozeDuration))s, ID=\(snoozeID)")
        } catch {
            DebugLog.shared.error("scheduleSnoozeAlarm: FAILED \(prayer.displayName): \(error)")
            throw error
        }
    }

    // MARK: - Test Alarm (Verification)

    /// Test F: Full config with corrected schedule offset.
    /// Schedule is offset by -preAlert so countdown starts early and alarm fires at fireTime.
    /// Expected: countdown LA at +1 min, counts down 2 min, alarm fires at +3 min.
    func scheduleTestAlarmCorrected(index: Int) async throws -> Date {
        let fireTime = Date.now.addingTimeInterval(3 * 60)
        let alarmID = UUID()
        let preAlertSeconds: TimeInterval = 2 * 60

        let alertPresentation = AlarmPresentation.Alert(
            title: "Test F-\(index)",
            stopButton: .prayerDismissButton,
            secondaryButton: .prayerSnoozeButton,
            secondaryButtonBehavior: .custom
        )
        let countdownPresentation = AlarmPresentation.Countdown(
            title: "Test F-\(index)"
        )
        let presentation = AlarmPresentation(
            alert: alertPresentation,
            countdown: countdownPresentation
        )
        let metadata = PrayerAlarmMetadata(
            prayer: .fajr,
            fireDate: fireTime,
            nextPrayer: .dhuhr,
            snoozeDurationSeconds: 300
        )
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: metadata,
            tintColor: Color.accentColor
        )

        // Offset: schedule starts countdown at fireTime - preAlert,
        // alarm fires preAlert seconds later = fireTime
        let schedule = Alarm.Schedule.fixed(fireTime.addingTimeInterval(-preAlertSeconds))

        let countdownDuration = Alarm.CountdownDuration(
            preAlert: preAlertSeconds,
            postAlert: 15 * 60
        )

        let stopIntent = DismissPrayerIntent(alarmID: alarmID.uuidString, entityName: "fajr")
        let secondaryIntent = SnoozePrayerIntent(alarmID: alarmID.uuidString, entityName: "fajr")

        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            stopIntent: stopIntent,
            secondaryIntent: secondaryIntent
        )

        _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
        let scheduleStart = fireTime.addingTimeInterval(-preAlertSeconds)
        DebugLog.shared.log("TestF: scheduled ID=\(alarmID), countdown at \(scheduleStart), alarm at \(fireTime), preAlert=\(Int(preAlertSeconds))s")
        persistAlarmID(alarmID, forKey: "test-\(index)", fireDate: fireTime)
        return fireTime
    }

    // MARK: - Cancel

    /// Cancels the active alarm for a given prayer, if one exists.
    /// Uses `cancel()` first (Apple's pattern for scheduled alarms), falls back to `stop()`.
    func cancelAlarm(for prayer: Prayer) async throws {
        guard let state = fetchAlarmState(for: prayer), let alarmID = state.alarmID else {
            return
        }

        // DEBUG: verbose cancel logging
        DebugLog.shared.log("cancelAlarm: \(prayer.displayName) ID=\(alarmID)")
        do {
            try AlarmManager.shared.cancel(id: alarmID)
            DebugLog.shared.log("cancelAlarm: cancel OK for \(prayer.displayName)")
        } catch {
            DebugLog.shared.error("cancelAlarm: cancel threw for \(prayer.displayName): \(error), trying stop()")
            do {
                try AlarmManager.shared.stop(id: alarmID)
                DebugLog.shared.log("cancelAlarm: stop OK for \(prayer.displayName)")
            } catch {
                DebugLog.shared.error("cancelAlarm: stop also threw for \(prayer.displayName): \(error)")
            }
        }

        localContext.delete(state)
        try localContext.save()
    }

    // MARK: - Stop All (Debug)

    /// Stops every alarm AlarmKit knows about and clears all local DeviceAlarmState records.
    /// Use to purge stale alarms from previous builds that reference deleted intent types.
    func stopAllAlarms() -> Int {
        // DEBUG: verbose stop-all logging
        DebugLog.shared.log("stopAllAlarms: starting")
        var count = 0

        // Stop everything AlarmKit currently tracks
        do {
            let alarms = try AlarmManager.shared.alarms
            DebugLog.shared.log("stopAllAlarms: AlarmKit reports \(alarms.count) alarms")
            for alarm in alarms {
                DebugLog.shared.log("  stopping \(alarm.id)")
                do {
                    try AlarmManager.shared.cancel(id: alarm.id)
                    DebugLog.shared.log("  cancel OK: \(alarm.id)")
                } catch {
                    DebugLog.shared.error("  cancel failed: \(error)")
                }
                do {
                    try AlarmManager.shared.stop(id: alarm.id)
                    DebugLog.shared.log("  stop OK: \(alarm.id)")
                } catch {
                    DebugLog.shared.error("  stop failed: \(error)")
                }
                count += 1
            }
        } catch {
            DebugLog.shared.error("stopAllAlarms: AlarmKit.alarms threw: \(error)")
        }

        // Clear all local records
        let device = deviceID
        let descriptor = FetchDescriptor<DeviceAlarmState>(
            predicate: #Predicate { $0.deviceID == device }
        )
        if let states = try? localContext.fetch(descriptor) {
            DebugLog.shared.log("stopAllAlarms: clearing \(states.count) local DeviceAlarmState records")
            for state in states {
                localContext.delete(state)
            }
            try? localContext.save()
        }

        activeAlarmIDs.removeAll()
        DebugLog.shared.log("stopAllAlarms: done, stopped \(count) alarm(s)")
        return count
    }

    // MARK: - Stale Cleanup

    /// Removes DeviceAlarmState records older than 24 hours and stops any lingering alarms.
    func cleanupStaleAlarms() {
        // DEBUG: verbose cleanup logging
        let cutoff = Date.now.addingTimeInterval(-24 * 60 * 60)
        let device = deviceID
        let descriptor = FetchDescriptor<DeviceAlarmState>(
            predicate: #Predicate { $0.deviceID == device && $0.lastScheduled != nil && $0.lastScheduled! < cutoff }
        )

        guard let staleStates = try? localContext.fetch(descriptor), !staleStates.isEmpty else {
            DebugLog.shared.log("cleanupStaleAlarms: nothing stale")
            return
        }

        DebugLog.shared.log("cleanupStaleAlarms: found \(staleStates.count) stale records")
        for state in staleStates {
            if let alarmID = state.alarmID {
                do {
                    try AlarmManager.shared.stop(id: alarmID)
                    DebugLog.shared.log("cleanupStaleAlarms: stopped \(alarmID)")
                } catch {
                    DebugLog.shared.error("cleanupStaleAlarms: stop threw for \(alarmID): \(error)")
                }
            }
            localContext.delete(state)
        }
        try? localContext.save()
        DebugLog.shared.log("cleanupStaleAlarms: cleaned up \(staleStates.count) records")
    }

    // MARK: - Snooze Duration (App Group)

    /// Writes snooze durations to App Group UserDefaults so widget extension intents can read them.
    private func writeSnoozeDurationsToAppGroup(_ configs: [PrayerAlarmConfig]) {
        guard let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) else { return }
        var durations: [String: Int] = [:]
        for config in configs {
            durations[config.prayerName] = config.snoozeDurationSeconds
        }
        suite.set(durations, forKey: "snoozeDurations")
    }

    // MARK: - Custom Reminder Alarms

    /// Schedules an AlarmKit alarm for an "urgent" custom reminder.
    func scheduleCustomReminderAlarm(_ reminder: CustomReminder) async throws {
        guard let time = reminder.scheduledTime, time > Date.now else { return }

        let alarmID = UUID()
        let stateKey = "reminder-\(reminder.id.uuidString)"

        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: reminder.title),
            stopButton: .prayerDismissButton
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

        let secondsUntil = time.timeIntervalSince(.now)
        let preAlertSeconds = min(Self.preAlertWindow, max(secondsUntil, 30))

        // Offset schedule by -preAlert so alarm fires at the intended time
        let schedule = Alarm.Schedule.fixed(time.addingTimeInterval(-preAlertSeconds))

        let countdownDuration = Alarm.CountdownDuration(
            preAlert: preAlertSeconds,
            postAlert: 4 * 60 * 60
        )

        let stopIntent = MarkDoneIntent(alarmID: alarmID.uuidString, entityName: stateKey)

        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            stopIntent: stopIntent
        )

        do {
            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            DebugLog.shared.log("scheduleCustomReminder: SUCCESS \(reminder.title) at \(time), ID=\(alarmID)")
        } catch {
            DebugLog.shared.error("scheduleCustomReminder: FAILED \(reminder.title): \(error)")
            throw error
        }

        persistAlarmID(alarmID, forKey: stateKey, fireDate: time)
    }

    /// Cancels the AlarmKit alarm for a custom reminder, if one exists.
    func cancelCustomReminderAlarm(reminderID: UUID) async throws {
        let stateKey = "reminder-\(reminderID.uuidString)"
        guard let state = fetchAlarmState(forKey: stateKey), let alarmID = state.alarmID else {
            return
        }

        do {
            try AlarmManager.shared.cancel(id: alarmID)
        } catch {
            do {
                try AlarmManager.shared.stop(id: alarmID)
                DebugLog.shared.log("cancelCustomReminder: stop OK for \(reminderID)")
            } catch {
                DebugLog.shared.error("cancelCustomReminder: stop also threw for \(reminderID): \(error)")
            }
        }

        localContext.delete(state)
        try localContext.save()
        DebugLog.shared.log("cancelCustomReminder: done for \(reminderID)")
    }

    // MARK: - Alarm Details (for debug UI)

    struct AlarmInfo: Identifiable {
        let id: UUID
        let label: String
        let lastScheduled: Date?
        let fireDate: Date?
        let isActive: Bool
    }

    /// Returns displayable info for all tracked alarms on this device.
    func fetchAlarmDetails() -> [AlarmInfo] {
        fetchAlarms()

        let device = deviceID
        let descriptor = FetchDescriptor<DeviceAlarmState>(
            predicate: #Predicate { $0.deviceID == device }
        )
        guard let states = try? localContext.fetch(descriptor) else { return [] }

        return states.compactMap { state in
            guard let alarmID = state.alarmID else { return nil }
            return AlarmInfo(
                id: alarmID,
                label: state.prayerName ?? "Unknown",
                lastScheduled: state.lastScheduled,
                fireDate: state.fireDate,
                isActive: activeAlarmIDs.contains(alarmID)
            )
        }
        .sorted { ($0.lastScheduled ?? .distantPast) > ($1.lastScheduled ?? .distantPast) }
    }

    // MARK: - Private helpers

    func fetchAlarmState(for prayer: Prayer) -> DeviceAlarmState? {
        return fetchAlarmState(forKey: prayer.rawValue)
    }

    func fetchAlarmState(forKey key: String) -> DeviceAlarmState? {
        let device = deviceID
        let descriptor = FetchDescriptor<DeviceAlarmState>(
            predicate: #Predicate { $0.prayerName == key && $0.deviceID == device }
        )
        return try? localContext.fetch(descriptor).first
    }

    private func persistAlarmID(_ id: UUID, for prayer: Prayer, fireDate: Date? = nil) {
        persistAlarmID(id, forKey: prayer.rawValue, fireDate: fireDate)
    }

    private func persistAlarmID(_ id: UUID, forKey key: String, fireDate: Date? = nil) {
        if let existing = fetchAlarmState(forKey: key) {
            existing.alarmID = id
            existing.lastScheduled = Date()
            existing.fireDate = fireDate
        } else {
            let state = DeviceAlarmState(
                prayerName: key,
                alarmID: id,
                deviceID: deviceID,
                fireDate: fireDate
            )
            localContext.insert(state)
        }
        try? localContext.save()
    }
}
