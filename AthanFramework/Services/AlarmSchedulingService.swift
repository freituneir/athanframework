import Foundation
import AlarmKit
import SwiftData
import SwiftUI

/// Schedules and manages AlarmKit alarms for the five daily prayers.
///
/// This is the core service that bridges prayer time data with iOS 26's AlarmKit.
/// It stores alarm IDs in a device-local `DeviceAlarmState` model so alarms can be
/// cancelled and rescheduled across app launches.
@Observable
@MainActor
final class AlarmSchedulingService {

    // MARK: - State

    /// Current authorization status, updated after requesting permission.
    private(set) var authorizationStatus: AlarmManager.AuthorizationStatus = .notDetermined

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
        let status = try await AlarmManager.shared.requestAuthorization()
        authorizationStatus = status
        return status == .authorized
    }

    // MARK: - Reconcile (main entry point)

    /// Cancels outdated alarms and schedules fresh ones for every enabled prayer.
    ///
    /// Call this whenever prayer times or alarm configs change (e.g. on app launch,
    /// after fetching new times, or when the user edits a config).
    func reconcileAlarms(
        prayerTimes: DailyPrayerTimes,
        configs: [PrayerAlarmConfig]
    ) async throws {
        for prayer in Prayer.allCases {
            guard let config = configs.first(where: { $0.prayerName == prayer.rawValue }) else {
                continue
            }

            // If the alarm is disabled, cancel any existing alarm for this prayer.
            guard config.isEnabled, let baseTime = prayerTimes.time(for: prayer) else {
                try await cancelAlarm(for: prayer)
                continue
            }

            // Apply offset.
            let scheduledTime = baseTime.addingTimeInterval(TimeInterval(config.offsetMinutes * 60))

            // Skip past times.
            guard scheduledTime > Date.now else {
                continue
            }

            // Cancel the previous alarm before scheduling a new one.
            try await cancelAlarm(for: prayer)
            try await scheduleAlarm(for: prayer, at: scheduledTime, config: config)
        }
    }

    // MARK: - Schedule

    /// Schedules a single AlarmKit alarm for a prayer.
    func scheduleAlarm(
        for prayer: Prayer,
        at time: Date,
        config: PrayerAlarmConfig
    ) async throws {
        let alarmID = UUID()

        // --- Schedule ---
        let schedule = Alarm.Schedule.fixed(time)

        // --- Buttons ---
        let stopButton = AlarmButton(
            text: "Done",
            textColor: .white,
            systemImageName: "checkmark.circle.fill"
        )

        let snoozeButton = AlarmButton(
            text: "Snooze",
            textColor: .white,
            systemImageName: "bell.and.waves.left.and.right.fill"
        )

        // --- Presentation ---
        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: "\(prayer.displayName) Prayer"),
            stopButton: stopButton,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .countdown
        )

        let countdownPresentation = AlarmPresentation.Countdown(
            title: LocalizedStringResource(stringLiteral: "\(prayer.displayName) Prayer")
        )

        let presentation = AlarmPresentation(
            alert: alertPresentation,
            countdown: countdownPresentation
        )

        // --- Attributes ---
        let tintColor = Color(hex: config.tintColorHex)
        let metadata = PrayerAlarmMetadata(prayer: prayer)

        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: metadata,
            tintColor: tintColor
        )

        // --- Countdown duration (snooze persistence) ---
        let countdownDuration = Alarm.CountdownDuration(
            preAlert: nil,
            postAlert: TimeInterval(config.snoozeDurationSeconds)
        )

        // --- Sound ---
        let sound = SoundManager.alertSound(for: config.soundFileName)

        // --- Stop intent ---
        let stopIntent = MarkPrayerDoneIntent(
            alarmIdentifier: alarmID.uuidString,
            prayerName: prayer.rawValue
        )

        // --- Configuration ---
        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            stopIntent: stopIntent,
            sound: sound
        )

        // Schedule with AlarmKit.
        _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)

        // Persist the alarm ID locally.
        persistAlarmID(alarmID, for: prayer)
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
            // The alarm may have already fired or been dismissed — that's fine.
        }

        localContext.delete(state)
        try localContext.save()
    }

    // MARK: - Alarm Updates

    /// Yields alarm state updates from AlarmKit. Useful for refreshing UI or
    /// triggering follow-up scheduling when an alarm fires or is dismissed.
    func observeAlarmUpdates() -> AlarmManager.AlarmUpdates {
        AlarmManager.shared.alarmUpdates
    }

    // MARK: - Private helpers

    private func fetchAlarmState(for prayer: Prayer) -> DeviceAlarmState? {
        let name = prayer.rawValue
        let device = deviceID
        let descriptor = FetchDescriptor<DeviceAlarmState>(
            predicate: #Predicate { $0.prayerName == name && $0.deviceID == device }
        )
        return try? localContext.fetch(descriptor).first
    }

    private func persistAlarmID(_ id: UUID, for prayer: Prayer) {
        // Upsert: update existing record or insert a new one.
        if let existing = fetchAlarmState(for: prayer) {
            existing.alarmID = id
            existing.lastScheduled = Date()
        } else {
            let state = DeviceAlarmState(
                prayerName: prayer.rawValue,
                alarmID: id,
                deviceID: deviceID
            )
            localContext.insert(state)
        }
        try? localContext.save()
    }
}
