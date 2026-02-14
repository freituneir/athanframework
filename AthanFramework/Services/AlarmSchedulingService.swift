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

    /// Cancels outdated alarms and schedules fresh ones for every enabled prayer.
    func reconcileAlarms(
        prayerTimes: DailyPrayerTimes,
        configs: [PrayerAlarmConfig]
    ) async throws {
        for prayer in Prayer.allCases {
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
        print("[AlarmKit] Scheduling alarm for \(prayer.displayName) at \(time)")
        let alarmID = UUID()

        let schedule = Alarm.Schedule.fixed(time)

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

        let tintColor = Color(hex: config.tintColorHex)
        let metadata = PrayerAlarmMetadata(prayer: prayer)
        
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: metadata,
            tintColor: tintColor
        )

        let countdownDuration = Alarm.CountdownDuration(
            preAlert: nil,
            postAlert: TimeInterval(config.snoozeDurationSeconds)
        )

        let stopIntent = MarkPrayerDoneIntent(
            alarmIdentifier: alarmID.uuidString,
            prayerName: prayer.rawValue
        )

        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            stopIntent: stopIntent
        )

        _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)

        persistAlarmID(alarmID, for: prayer)
        print("[AlarmKit] Alarm scheduled for \(prayer.displayName) with ID \(alarmID)")
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
        let schedule = Alarm.Schedule.fixed(time)
        let stateKey = "reminder-\(reminder.id.uuidString)"

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

        let alertPresentation = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: reminder.title),
            stopButton: stopButton,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .countdown
        )

        let countdownPresentation = AlarmPresentation.Countdown(
            title: LocalizedStringResource(stringLiteral: reminder.title)
        )

        let presentation = AlarmPresentation(
            alert: alertPresentation,
            countdown: countdownPresentation
        )

        let metadata = ReminderAlarmMetadata(title: reminder.title)

        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: metadata,
            tintColor: Color(hex: AppConstants.Defaults.tintColorHex)
        )

        let countdownDuration = Alarm.CountdownDuration(
            preAlert: nil,
            postAlert: TimeInterval(reminder.snoozeDurationSeconds)
        )

        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes
        )

        _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)

        persistAlarmID(alarmID, forKey: stateKey)
        print("[AlarmKit] Urgent reminder alarm scheduled: \(reminder.title) at \(time) with ID \(alarmID)")
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
