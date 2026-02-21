import Foundation
import SwiftData
import SwiftUI
import UserNotifications
import AlarmKit
import ActivityKit

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
            // Update synchronously — avoids race where reconcileAlarms() reads
            // stale activeAlarmIDs before an unstructured Task can execute.
            updateAlarmState(with: remoteAlarms)
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
        tomorrowFajrTime: Date? = nil,
        athanSound: AthanSound = .defaultTone
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
                rawPrayerTime: baseTime,
                config: config,
                nextPrayer: nextPrayer,
                nextPrayerTime: nextPrayerTime,
                athanSound: athanSound
            )
        }
    }

    // MARK: - Schedule

    // MARK: - Stop Past-Due Prayer LAs

    /// Stops ALL existing prayer + followup + reminder alarm Live Activities.
    /// Used by the debug "Stop All" feature. Does NOT mark prayers as done.
    func stopAllPrayerAlarms() {
        let device = deviceID
        let prayerNames = Set(Prayer.allCases.map(\.rawValue))
        let followupNames = Set(Prayer.allCases.map { "followup-\($0.rawValue)" })
        let reminderNames = Set(Prayer.allCases.map { "reminder-\($0.rawValue)" })
        let targetNames = prayerNames.union(followupNames).union(reminderNames)

        let descriptor = FetchDescriptor<DeviceAlarmState>(
            predicate: #Predicate { $0.deviceID == device }
        )
        guard let allStates = try? localContext.fetch(descriptor), !allStates.isEmpty else { return }

        for state in allStates {
            let name = state.prayerName
            guard targetNames.contains(name) else { continue }
            if let alarmID = state.alarmID {
                DebugLog.shared.log("stopAllPrayer: stopping \(name) LA (ID=\(alarmID))")
                try? AlarmManager.shared.stop(id: alarmID)
            }
            localContext.delete(state)
        }
        try? localContext.save()

        // Clean up App Group keys for followups, reminders, and fired alarms
        if let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) {
            for prayer in Prayer.allCases {
                suite.removeObject(forKey: AppConstants.AppGroup.followupAlarmIDKey(for: prayer.rawValue))
                suite.removeObject(forKey: AppConstants.AppGroup.reminderAlarmIDKey(for: prayer.rawValue))
                suite.removeObject(forKey: AppConstants.AppGroup.reminderFireDateKey(for: prayer.rawValue))
            }
            suite.removeObject(forKey: AppConstants.AppGroup.firedAlarmsKey)
        }
    }

    /// Schedules a single AlarmKit alarm for a prayer.
    /// Uses Schedule.fixed() so the alarm fires at the exact prayer time,
    /// plus CountdownDuration with a 5-minute preAlert and 24-hour postAlert
    /// (LA stays alive through dismiss; daily cleanup handles stale alarms).
    func scheduleAlarm(
        for prayer: Prayer,
        at time: Date,
        rawPrayerTime: Date? = nil,
        config: PrayerAlarmConfig,
        nextPrayer: Prayer? = nil,
        nextPrayerTime: Date? = nil,
        athanSound: AthanSound = .defaultTone
    ) async throws {
        // NOTE: We no longer call stopAllPrayerAlarms() here.
        // reconcileAlarms() handles per-prayer cleanup via cancelAlarm(for:) before calling this.
        // Followup LAs (for uncompleted prayers) use a separate namespace and must survive.

        // DEBUG: verbose schedule logging
        DebugLog.shared.log("scheduleAlarm: \(prayer.displayName) at \(time), auth=\(isAuthorized)")
        let alarmID = UUID()

        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: "\(prayer.displayName) Prayer"),
            stopButton: .prayerDismissButton,
            secondaryButton: .prayerSnoozeButton,
            secondaryButtonBehavior: .countdown
        )

        let countdownPresentation = AlarmPresentation.Countdown(
            title: LocalizedStringResource(stringLiteral: "\(prayer.displayName) Prayer")
        )

        let presentation = AlarmPresentation(
            alert: alertPresentation,
            countdown: countdownPresentation
        )

        let tintColor = Color(hex: config.tintColorHex)

        // preAlert: LA countdown appears before alarm, capped at actual time remaining
        let secondsUntil = time.timeIntervalSince(.now)
        let preAlertSeconds = min(Self.preAlertWindow, max(secondsUntil, 30))

        // postAlert = snooze duration (AlarmKit restarts countdown with this interval on snooze tap)
        let postAlertSeconds = TimeInterval(config.snoozeDurationSeconds)

        // Format next prayer time for Live Activity display
        let nextPrayerTimeStr: String
        if let nextTime = nextPrayerTime {
            nextPrayerTimeStr = DateFormatter.prayerTime.string(from: nextTime)
        } else {
            nextPrayerTimeStr = ""
        }

        let metadata = PrayerAlarmMetadata(
            prayer: prayer,
            fireDate: time,
            rawPrayerTime: rawPrayerTime,
            nextPrayer: nextPrayer,
            nextPrayerTimeString: nextPrayerTimeStr,
            snoozeDurationSeconds: config.snoozeDurationSeconds,
            preAlertSeconds: preAlertSeconds
        )

        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: metadata,
            tintColor: tintColor
        )

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
            secondaryIntent: secondaryIntent,
            sound: athanSound.alertSound
        )

        do {
            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            DebugLog.shared.log("scheduleAlarm: SUCCESS \(prayer.displayName) ID=\(alarmID), preAlert=\(Int(preAlertSeconds))s, sound=\(athanSound.rawValue)")
        } catch {
            DebugLog.shared.error("scheduleAlarm: FAILED \(prayer.displayName): \(error)")
            throw error
        }

        persistAlarmID(alarmID, for: prayer, fireDate: time)
        writeLastFiredAlarm(prayer: prayer, fireDate: time)
    }

    // MARK: - Proactive Reminder Alarm

    /// Reads the reminder delay (minutes) from App Group UserDefaults.
    func readReminderDelay() -> Int {
        guard let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) else { return 5 }
        let value = suite.integer(forKey: AppConstants.AppGroup.reminderDelayKey)
        return value > 0 ? value : 5
    }

    /// Schedules a silent reminder alarm that shows "Pray Now" LA if the prayer isn't done.
    /// Similar to scheduleRecoveryAlarm() but scheduled proactively at alarm creation time.
    func scheduleReminderAlarm(
        for prayer: Prayer,
        at reminderTime: Date,
        prayerFireDate: Date,
        config: PrayerAlarmConfig,
        nextPrayer: Prayer? = nil,
        nextPrayerTime: Date? = nil
    ) async throws {
        // Cancel any existing reminder for this prayer
        try await cancelReminderAlarm(for: prayer)

        let alarmID = UUID()
        let stateKey = "reminder-\(prayer.rawValue)"

        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: "\(prayer.displayName) Prayer"),
            stopButton: .prayerDismissButton,
            secondaryButton: .prayerSnoozeButton,
            secondaryButtonBehavior: .countdown
        )

        let countdownPresentation = AlarmPresentation.Countdown(
            title: LocalizedStringResource(stringLiteral: "\(prayer.displayName) Prayer")
        )

        let presentation = AlarmPresentation(
            alert: alertPresentation,
            countdown: countdownPresentation
        )

        let tintColor = Color(hex: config.tintColorHex)

        // Format next prayer time
        let nextPrayerTimeStr: String
        if let nextTime = nextPrayerTime {
            nextPrayerTimeStr = DateFormatter.prayerTime.string(from: nextTime)
        } else {
            nextPrayerTimeStr = ""
        }

        // fireDate = original prayer time (past at reminder time) → shows "Pray Now" + count-up
        let metadata = PrayerAlarmMetadata(
            prayer: prayer,
            fireDate: prayerFireDate,
            nextPrayer: nextPrayer,
            nextPrayerTimeString: nextPrayerTimeStr,
            snoozeDurationSeconds: config.snoozeDurationSeconds,
            preAlertSeconds: 4 * 3600
        )

        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: metadata,
            tintColor: tintColor
        )

        // Use a long preAlert so the alarm stays in countdown mode — no system alert fires.
        // The LA appears silently; the widget renders post-alert UI because fireDate is in the past.
        let preAlertSeconds: TimeInterval = 4 * 3600
        let postAlertSeconds = TimeInterval(config.snoozeDurationSeconds)

        let schedule = Alarm.Schedule.fixed(reminderTime)

        let countdownDuration = Alarm.CountdownDuration(
            preAlert: preAlertSeconds,
            postAlert: postAlertSeconds
        )

        let stopIntent = DismissPrayerIntent(alarmID: alarmID.uuidString, entityName: prayer.rawValue)
        let secondaryIntent = SnoozePrayerIntent(alarmID: alarmID.uuidString, entityName: prayer.rawValue)

        // No sound — silent reminder
        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            stopIntent: stopIntent,
            secondaryIntent: secondaryIntent
        )

        do {
            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            DebugLog.shared.log("reminderAlarm: SUCCESS \(prayer.displayName) at \(reminderTime), ID=\(alarmID)")
        } catch {
            DebugLog.shared.error("reminderAlarm: FAILED \(prayer.displayName): \(error)")
            throw error
        }

        // Persist locally for cleanup
        persistAlarmID(alarmID, forKey: stateKey, fireDate: reminderTime)

        // Write to App Group so intents (MarkDone, Snooze) can cancel/reschedule
        writeReminderToAppGroup(prayer: prayer, alarmID: alarmID, prayerFireDate: prayerFireDate)
    }

    /// Cancels the reminder alarm for a prayer, if one exists.
    /// Checks both SwiftData and App Group (intent may have rescheduled with a different ID).
    func cancelReminderAlarm(for prayer: Prayer) async throws {
        let stateKey = "reminder-\(prayer.rawValue)"
        let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName)

        // Cancel from SwiftData state
        if let state = fetchAlarmState(forKey: stateKey), let alarmID = state.alarmID {
            try? AlarmManager.shared.cancel(id: alarmID)
            try? AlarmManager.shared.stop(id: alarmID)
            localContext.delete(state)
            try? localContext.save()
            DebugLog.shared.log("cancelReminder: cancelled SwiftData alarm for \(prayer.displayName)")
        }

        // Also cancel from App Group (SnoozePrayerIntent may have rescheduled with a new ID)
        if let reminderIDStr = suite?.string(forKey: AppConstants.AppGroup.reminderAlarmIDKey(for: prayer.rawValue)),
           let reminderUUID = UUID(uuidString: reminderIDStr) {
            try? AlarmManager.shared.cancel(id: reminderUUID)
            try? AlarmManager.shared.stop(id: reminderUUID)
            DebugLog.shared.log("cancelReminder: cancelled App Group alarm for \(prayer.displayName)")
        }

        // Clean up App Group
        suite?.removeObject(forKey: AppConstants.AppGroup.reminderAlarmIDKey(for: prayer.rawValue))
        suite?.removeObject(forKey: AppConstants.AppGroup.reminderFireDateKey(for: prayer.rawValue))
    }

    /// Writes reminder alarm metadata to App Group so intents can manage push-back.
    private func writeReminderToAppGroup(prayer: Prayer, alarmID: UUID, prayerFireDate: Date) {
        guard let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) else { return }
        suite.set(alarmID.uuidString, forKey: AppConstants.AppGroup.reminderAlarmIDKey(for: prayer.rawValue))
        suite.set(prayerFireDate.timeIntervalSince1970, forKey: AppConstants.AppGroup.reminderFireDateKey(for: prayer.rawValue))
    }

    // MARK: - Recovery Alarm (Silent LA)

    /// Schedules a silent Live Activity that shows "Pray Now" + Done for a missed prayer.
    /// Uses a long preAlert (4h) so the alarm stays in countdown mode — no system alert fires.
    /// The widget shows post-alert UI because `metadata.fireDate` is in the past.
    func scheduleRecoveryAlarm(
        for prayer: Prayer,
        originalFireDate: Date,
        config: PrayerAlarmConfig,
        nextPrayer: Prayer?,
        nextPrayerTime: Date?,
        athanSound: AthanSound
    ) async throws {
        let alarmID = UUID()

        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: "\(prayer.displayName) Prayer"),
            stopButton: .prayerDismissButton,
            secondaryButton: .prayerSnoozeButton,
            secondaryButtonBehavior: .countdown
        )

        let countdownPresentation = AlarmPresentation.Countdown(
            title: LocalizedStringResource(stringLiteral: "\(prayer.displayName) Prayer")
        )

        let presentation = AlarmPresentation(
            alert: alertPresentation,
            countdown: countdownPresentation
        )

        let tintColor = Color(hex: config.tintColorHex)

        // Format next prayer time for Live Activity display
        let nextPrayerTimeStr: String
        if let nextTime = nextPrayerTime {
            nextPrayerTimeStr = DateFormatter.prayerTime.string(from: nextTime)
        } else {
            nextPrayerTimeStr = ""
        }

        // fireDate = originalFireDate (past) → isPostAlert() returns true → "Pray Now" + Done
        let metadata = PrayerAlarmMetadata(
            prayer: prayer,
            fireDate: originalFireDate,
            nextPrayer: nextPrayer,
            nextPrayerTimeString: nextPrayerTimeStr,
            snoozeDurationSeconds: config.snoozeDurationSeconds,
            preAlertSeconds: 4 * 3600
        )

        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: metadata,
            tintColor: tintColor
        )

        // preAlert = 4 hours — alarm stays in countdown mode, no system alert
        let preAlertSeconds: TimeInterval = 4 * 3600
        let postAlertSeconds = TimeInterval(config.snoozeDurationSeconds)

        // Schedule immediately — countdown starts now, LA appears
        let schedule = Alarm.Schedule.fixed(Date.now)

        let countdownDuration = Alarm.CountdownDuration(
            preAlert: preAlertSeconds,
            postAlert: postAlertSeconds
        )

        let stopIntent = DismissPrayerIntent(alarmID: alarmID.uuidString, entityName: prayer.rawValue)
        let secondaryIntent = SnoozePrayerIntent(alarmID: alarmID.uuidString, entityName: prayer.rawValue)

        // No sound parameter — silent recovery
        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            stopIntent: stopIntent,
            secondaryIntent: secondaryIntent
        )

        do {
            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            DebugLog.shared.log("recoveryAlarm: SUCCESS \(prayer.displayName) ID=\(alarmID)")
        } catch {
            DebugLog.shared.error("recoveryAlarm: FAILED \(prayer.displayName): \(error)")
            throw error
        }

        // Persist under followup namespace so it survives per-prayer cancelAlarm() calls
        let followupKey = "followup-\(prayer.rawValue)"
        persistAlarmID(alarmID, forKey: followupKey, fireDate: Date.now.addingTimeInterval(4 * 3600))
        writeFollowupToAppGroup(prayer: prayer, alarmID: alarmID)
        DebugLog.shared.log("recoveryAlarm: persisted as \(followupKey), wrote to App Group")
        // Do NOT call writeLastFiredAlarm() — avoid overwriting tracking data
    }

    // MARK: - Followup Alarm Helpers

    /// Writes the followup alarm ID to App Group so MarkDoneIntent (widget extension) can cancel it.
    private func writeFollowupToAppGroup(prayer: Prayer, alarmID: UUID) {
        guard let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) else { return }
        suite.set(alarmID.uuidString, forKey: AppConstants.AppGroup.followupAlarmIDKey(for: prayer.rawValue))
        DebugLog.shared.log("followup: wrote \(prayer.displayName) ID=\(alarmID) to App Group")
    }

    /// Cancels the followup (recovery) alarm for a prayer, if one exists.
    func cancelFollowupAlarm(for prayer: Prayer) {
        let followupKey = "followup-\(prayer.rawValue)"
        if let state = fetchAlarmState(forKey: followupKey), let alarmID = state.alarmID {
            DebugLog.shared.log("cancelFollowup: stopping \(prayer.displayName) ID=\(alarmID)")
            try? AlarmManager.shared.cancel(id: alarmID)
            try? AlarmManager.shared.stop(id: alarmID)
            localContext.delete(state)
            try? localContext.save()
        }
        // Also clean up App Group
        if let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) {
            suite.removeObject(forKey: AppConstants.AppGroup.followupAlarmIDKey(for: prayer.rawValue))
        }
    }

    /// Whether a followup alarm is active for this prayer.
    func hasActiveFollowup(for prayer: Prayer) -> Bool {
        let followupKey = "followup-\(prayer.rawValue)"
        guard let existingID = fetchAlarmState(forKey: followupKey)?.alarmID else { return false }
        return activeAlarmIDs.contains(existingID)
    }

    // MARK: - Fired Alarm Tracking (App Group)

    /// Writes a per-prayer fired alarm entry to App Group so recovery can work for any prayer,
    /// not just the last scheduled one. Key: "firedAlarms" -> [String: Double] (prayer -> timestamp).
    private func writeLastFiredAlarm(prayer: Prayer, fireDate: Date) {
        guard let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) else { return }
        var firedAlarms = suite.dictionary(forKey: AppConstants.AppGroup.firedAlarmsKey) as? [String: Double] ?? [:]
        firedAlarms[prayer.rawValue] = fireDate.timeIntervalSince1970
        suite.set(firedAlarms, forKey: AppConstants.AppGroup.firedAlarmsKey)
        DebugLog.shared.log("firedAlarms: wrote \(prayer.displayName) at \(fireDate)")
    }

    // MARK: - Standalone "Pray Now" Live Activity (ActivityKit, no AlarmKit)

    /// Schedules a standalone "Pray Now" Live Activity for a prayer.
    /// Uses plain ActivityKit — completely independent of AlarmKit alarms.
    /// The LA appears at `prayerTime` and persists until Done is tapped.
    func schedulePrayNowActivity(for prayer: Prayer, rawPrayerTime: Date) {
        // Don't schedule if prayer time is from a previous day
        let todayStart = Calendar.current.startOfDay(for: Date.now)
        guard rawPrayerTime >= todayStart else {
            DebugLog.shared.log("prayNow: \(prayer.displayName) is from a previous day, skipping")
            return
        }

        // Don't schedule if one already exists for this prayer
        for activity in Activity<PrayNowAttributes>.activities {
            if activity.attributes.prayerName == prayer.rawValue {
                DebugLog.shared.log("prayNow: \(prayer.displayName) already has active LA, skipping")
                return
            }
        }

        let attributes = PrayNowAttributes(
            prayerName: prayer.rawValue,
            rawPrayerTime: rawPrayerTime
        )
        let initialState = PrayNowAttributes.ContentState(isActive: true)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: todayStart) ?? Date.now.addingTimeInterval(24 * 3600)
        let content = ActivityContent(state: initialState, staleDate: endOfDay)

        do {
            _ = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            DebugLog.shared.log("prayNow: scheduled \(prayer.displayName) LA, rawTime=\(rawPrayerTime)")
        } catch {
            DebugLog.shared.error("prayNow: failed to schedule \(prayer.displayName): \(error)")
        }
    }

    /// Ends the "Pray Now" Live Activity for a prayer (called when marking done).
    func endPrayNowActivity(for prayer: Prayer) {
        for activity in Activity<PrayNowAttributes>.activities {
            if activity.attributes.prayerName == prayer.rawValue {
                let finalState = PrayNowAttributes.ContentState(isActive: false)
                Task {
                    await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
                }
                DebugLog.shared.log("prayNow: ended \(prayer.displayName) LA")
            }
        }
    }

    /// Ends all "Pray Now" Live Activities (for debug "Stop All").
    func endAllPrayNowActivities() {
        for activity in Activity<PrayNowAttributes>.activities {
            let finalState = PrayNowAttributes.ContentState(isActive: false)
            Task {
                await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
        DebugLog.shared.log("prayNow: ended all Pray Now LAs")
    }

    /// Reconciles "Pray Now" LAs: schedule for past uncompleted prayers, end for completed ones.
    /// Appears when the RAW prayer time has passed (ignores user offset).
    /// Offset only affects when the AlarmKit alarm fires — not the count-up LA.
    func reconcilePrayNowActivities(prayerTimes: DailyPrayerTimes, completedPrayers: Set<String>) {
        for prayer in Prayer.allCases {
            guard let baseTime = prayerTimes.time(for: prayer) else { continue }

            if completedPrayers.contains(prayer.rawValue) {
                endPrayNowActivity(for: prayer)
            } else if baseTime <= Date.now {
                schedulePrayNowActivity(for: prayer, rawPrayerTime: baseTime)
            }
        }
    }

    // MARK: - Test Alarm (Verification)

    /// Test alarm: countdown LA appears at +30s, alarm fires at +90s.
    /// Snooze: 30s. Uses "fajr" entity so Dismiss/Snooze/Done intents work.
    /// Also schedules a standalone "Pray Now" LA at fire time.
    func scheduleTestAlarmCorrected(index: Int, athanSound: AthanSound = .defaultTone) async throws -> Date {
        let fireTime = Date.now.addingTimeInterval(90)
        let alarmID = UUID()
        let preAlertSeconds: TimeInterval = 60
        let snoozeSeconds: TimeInterval = 30

        let alertPresentation = AlarmPresentation.Alert(
            title: "Test-\(index): Fajr",
            stopButton: .prayerDismissButton,
            secondaryButton: .prayerSnoozeButton,
            secondaryButtonBehavior: .countdown
        )
        let countdownPresentation = AlarmPresentation.Countdown(
            title: "Test-\(index): Fajr"
        )
        let presentation = AlarmPresentation(
            alert: alertPresentation,
            countdown: countdownPresentation
        )
        // rawPrayerTime = fireTime so the count-up LA starts counting from fire time
        let rawPrayerTime = fireTime
        let metadata = PrayerAlarmMetadata(
            prayer: .fajr,
            fireDate: fireTime,
            rawPrayerTime: rawPrayerTime,
            nextPrayer: .dhuhr,
            snoozeDurationSeconds: Int(snoozeSeconds),
            preAlertSeconds: preAlertSeconds
        )
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: metadata,
            tintColor: Color.accentColor
        )

        let schedule = Alarm.Schedule.fixed(fireTime.addingTimeInterval(-preAlertSeconds))
        let countdownDuration = Alarm.CountdownDuration(
            preAlert: preAlertSeconds,
            postAlert: snoozeSeconds
        )

        let stopIntent = DismissPrayerIntent(alarmID: alarmID.uuidString, entityName: "fajr")
        let secondaryIntent = SnoozePrayerIntent(alarmID: alarmID.uuidString, entityName: "fajr")

        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            stopIntent: stopIntent,
            secondaryIntent: secondaryIntent,
            sound: athanSound.alertSound
        )

        _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
        DebugLog.shared.log("Test: scheduled ID=\(alarmID), countdown at \(fireTime.addingTimeInterval(-preAlertSeconds)), alarm at \(fireTime), snooze=\(Int(snoozeSeconds))s")
        persistAlarmID(alarmID, forKey: "test-\(index)", fireDate: fireTime)
        writeLastFiredAlarm(prayer: .fajr, fireDate: fireTime)

        // Schedule the standalone "Pray Now" LA at fire time
        // Uses a delayed Task so it appears when the alarm fires, not immediately
        Task {
            let delay = fireTime.timeIntervalSince(.now)
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            schedulePrayNowActivity(for: .fajr, rawPrayerTime: fireTime)
        }

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

        // Also end all standalone "Pray Now" ActivityKit LAs
        endAllPrayNowActivities()

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
