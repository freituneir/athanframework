import Foundation
import SwiftData
import Testing
@testable import AthanFramework

// MARK: - AlarmSchedulingService Tests
//
// AlarmSchedulingService is @MainActor and depends on AlarmKit (device-only framework),
// so these tests validate the models and logic it relies on:
//   - PrayerAlarmConfig (per-prayer settings)
//   - DeviceAlarmState (local alarm ID persistence)
//   - Offset application (the TimeInterval formula used in reconcileAlarms)
//   - Config-matching and filtering logic

// MARK: - PrayerAlarmConfig Model Tests

struct PrayerAlarmConfigTests {

    @Test("Convenience init sets prayer name and snooze duration")
    func convenienceInit() {
        let config = PrayerAlarmConfig(prayer: .fajr)

        #expect(config.prayerName == "fajr")
        #expect(config.snoozeDurationSeconds == 120) // Fajr-specific
        #expect(config.isEnabled == true)
        #expect(config.soundFileName == "default_athan")
        #expect(config.offsetMinutes == 0)
        #expect(config.escalationEnabled == true)
    }

    @Test("Convenience init uses correct snooze for non-Fajr prayers")
    func convenienceInitNonFajr() {
        for prayer in Prayer.allCases where prayer != .fajr {
            let config = PrayerAlarmConfig(prayer: prayer)
            #expect(config.snoozeDurationSeconds == 300,
                    "\(prayer.displayName) should have 300s snooze")
        }
    }

    @Test("prayer computed property returns correct Prayer enum")
    func prayerComputedProperty() {
        for prayer in Prayer.allCases {
            let config = PrayerAlarmConfig(prayer: prayer)
            #expect(config.prayer == prayer)
        }
    }

    @Test("prayer computed property returns nil for invalid prayer name")
    func prayerComputedPropertyInvalid() {
        let config = PrayerAlarmConfig()
        config.prayerName = "invalid_prayer"
        #expect(config.prayer == nil)
    }

    @Test("Default tint color matches app constant")
    func defaultTintColor() {
        let config = PrayerAlarmConfig()
        #expect(config.tintColorHex == AppConstants.Defaults.tintColorHex)
    }

    @Test("Config can be disabled")
    func disableConfig() {
        let config = PrayerAlarmConfig(prayer: .fajr)
        config.isEnabled = false
        #expect(config.isEnabled == false)
    }

    @Test("Offset can be negative for pre-prayer alarms")
    func negativeOffset() {
        let config = PrayerAlarmConfig(prayer: .fajr)
        config.offsetMinutes = -30
        #expect(config.offsetMinutes == -30)
    }
}

// MARK: - DeviceAlarmState Model Tests

struct DeviceAlarmStateTests {

    @Test("Convenience init populates all fields")
    func convenienceInit() {
        let alarmID = UUID()
        let state = DeviceAlarmState(prayerName: "fajr", alarmID: alarmID, deviceID: "test-device")

        #expect(state.prayerName == "fajr")
        #expect(state.alarmID == alarmID)
        #expect(state.deviceID == "test-device")
        #expect(state.lastScheduled != nil)
    }

    @Test("Default init has empty values")
    func defaultInit() {
        let state = DeviceAlarmState()

        #expect(state.prayerName == "")
        #expect(state.alarmID == nil)
        #expect(state.deviceID == "")
        #expect(state.lastScheduled == nil)
    }

    @Test("Multiple states can coexist for different prayers")
    func multipleStatesPerPrayer() throws {
        let schema = Schema([DeviceAlarmState.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        for prayer in Prayer.allCases {
            let state = DeviceAlarmState(
                prayerName: prayer.rawValue,
                alarmID: UUID(),
                deviceID: "test-device"
            )
            context.insert(state)
        }

        try context.save()

        let descriptor = FetchDescriptor<DeviceAlarmState>()
        let states = try context.fetch(descriptor)
        #expect(states.count == 5)
    }
}

// MARK: - Alarm Scheduling Logic Tests
//
// These test the calculations that the AlarmSchedulingService would use:
// applying offsets, determining which alarms to schedule, etc.

struct AlarmSchedulingLogicTests {

    @Test("Applying a positive offset shifts alarm time forward")
    func positiveOffsetShiftsForward() {
        let baseTime = Date()
        let offsetMinutes = 15
        let adjustedTime = baseTime.addingTimeInterval(Double(offsetMinutes) * 60)

        #expect(adjustedTime > baseTime)
        #expect(adjustedTime.timeIntervalSince(baseTime) == 15 * 60)
    }

    @Test("Applying a negative offset shifts alarm time backward")
    func negativeOffsetShiftsBackward() {
        let baseTime = Date()
        let offsetMinutes = -30
        let adjustedTime = baseTime.addingTimeInterval(Double(offsetMinutes) * 60)

        #expect(adjustedTime < baseTime)
        #expect(baseTime.timeIntervalSince(adjustedTime) == 30 * 60)
    }

    @Test("Only enabled configs should produce alarms")
    func onlyEnabledConfigsProduceAlarms() {
        var configs: [PrayerAlarmConfig] = []
        for prayer in Prayer.allCases {
            let config = PrayerAlarmConfig(prayer: prayer)
            // Disable Dhuhr and Asr
            if prayer == .dhuhr || prayer == .asr {
                config.isEnabled = false
            }
            configs.append(config)
        }

        let enabledConfigs = configs.filter { $0.isEnabled }
        #expect(enabledConfigs.count == 3) // Fajr, Maghrib, Isha
    }

    @Test("Configs can be sorted by prayer sort order")
    func configsSortBySortOrder() {
        var configs: [PrayerAlarmConfig] = []
        // Insert in reverse order
        for prayer in Prayer.allCases.reversed() {
            configs.append(PrayerAlarmConfig(prayer: prayer))
        }

        let sorted = configs.sorted {
            ($0.prayer?.sortOrder ?? 0) < ($1.prayer?.sortOrder ?? 0)
        }

        #expect(sorted[0].prayerName == "fajr")
        #expect(sorted[1].prayerName == "dhuhr")
        #expect(sorted[2].prayerName == "asr")
        #expect(sorted[3].prayerName == "maghrib")
        #expect(sorted[4].prayerName == "isha")
    }

    @Test("Offset formula matches reconcileAlarms implementation: TimeInterval(offsetMinutes * 60)")
    func offsetFormulaMatchesImplementation() {
        let baseTime = Date()
        let config = PrayerAlarmConfig(prayer: .fajr)
        config.offsetMinutes = -15

        // This is the exact formula from AlarmSchedulingService.reconcileAlarms
        let scheduledTime = baseTime.addingTimeInterval(TimeInterval(config.offsetMinutes * 60))

        #expect(scheduledTime == baseTime.addingTimeInterval(-15 * 60))
    }

    @Test("reconcileAlarms skips past times (scheduledTime > Date.now)")
    func reconcileSkipsPastTimes() {
        let pastTime = Date().addingTimeInterval(-3600) // 1 hour ago
        let config = PrayerAlarmConfig(prayer: .fajr)
        config.offsetMinutes = 0

        let scheduledTime = pastTime.addingTimeInterval(TimeInterval(config.offsetMinutes * 60))
        // The service checks: guard scheduledTime > Date.now
        #expect(scheduledTime <= Date.now)
    }

    @Test("reconcileAlarms allows future times")
    func reconcileAllowsFutureTimes() {
        let futureTime = Date().addingTimeInterval(3600) // 1 hour from now
        let config = PrayerAlarmConfig(prayer: .fajr)
        config.offsetMinutes = 0

        let scheduledTime = futureTime.addingTimeInterval(TimeInterval(config.offsetMinutes * 60))
        #expect(scheduledTime > Date.now)
    }

    @Test("Config matching uses prayerName == prayer.rawValue")
    func configMatchingLogic() {
        let configs = Prayer.allCases.map { PrayerAlarmConfig(prayer: $0) }

        for prayer in Prayer.allCases {
            let matched = configs.first(where: { $0.prayerName == prayer.rawValue })
            #expect(matched != nil, "Should find config for \(prayer.displayName)")
            #expect(matched?.prayer == prayer)
        }
    }

    @Test("Disabled config with nil prayer time triggers cancel path")
    func disabledConfigTriggersCancel() {
        let config = PrayerAlarmConfig(prayer: .dhuhr)
        config.isEnabled = false

        let entry = DailyPrayerTimes()
        entry.dhuhr = Date().addingTimeInterval(3600)

        // The guard in reconcileAlarms: guard config.isEnabled, let baseTime = ...
        // With isEnabled == false, it should fall through to cancel path
        let shouldCancel = !config.isEnabled || entry.time(for: .dhuhr) == nil
        #expect(shouldCancel == true)
    }

    @Test("Enabled config with nil prayer time triggers cancel path")
    func nilPrayerTimeTriggersCancel() {
        let config = PrayerAlarmConfig(prayer: .dhuhr)
        config.isEnabled = true

        let entry = DailyPrayerTimes()
        // dhuhr is not set, so it's nil

        let shouldCancel = !config.isEnabled || entry.time(for: .dhuhr) == nil
        #expect(shouldCancel == true)
    }

    @Test("Enabled config with valid future time proceeds to schedule")
    func validFutureTimeProceeds() {
        let config = PrayerAlarmConfig(prayer: .dhuhr)
        config.isEnabled = true
        config.offsetMinutes = 0

        let entry = DailyPrayerTimes()
        let futureTime = Date().addingTimeInterval(3600)
        entry.dhuhr = futureTime

        let baseTime = entry.time(for: .dhuhr)!
        let scheduledTime = baseTime.addingTimeInterval(TimeInterval(config.offsetMinutes * 60))

        let shouldSchedule = config.isEnabled && baseTime != nil && scheduledTime > Date.now
        #expect(shouldSchedule == true)
    }

    @Test("Full reconcile simulation iterates all 5 prayers")
    func fullReconcileSimulation() {
        let entry = DailyPrayerTimes()
        let base = Date().addingTimeInterval(3600) // 1 hour from now

        entry.fajr = base
        entry.dhuhr = base.addingTimeInterval(3600 * 5)
        entry.asr = base.addingTimeInterval(3600 * 8)
        entry.maghrib = base.addingTimeInterval(3600 * 11)
        entry.isha = base.addingTimeInterval(3600 * 12)

        let configs = Prayer.allCases.map { PrayerAlarmConfig(prayer: $0) }

        var toSchedule: [(Prayer, Date)] = []
        var toCancel: [Prayer] = []

        // Simulate the reconcileAlarms loop
        for prayer in Prayer.allCases {
            guard let config = configs.first(where: { $0.prayerName == prayer.rawValue }) else {
                continue
            }

            guard config.isEnabled, let baseTime = entry.time(for: prayer) else {
                toCancel.append(prayer)
                continue
            }

            let scheduledTime = baseTime.addingTimeInterval(TimeInterval(config.offsetMinutes * 60))

            guard scheduledTime > Date.now else {
                continue
            }

            toSchedule.append((prayer, scheduledTime))
        }

        // All 5 prayers should be scheduled (all enabled, all in the future)
        #expect(toSchedule.count == 5)
        #expect(toCancel.isEmpty)
    }
}

// MARK: - PreAlert Computation Edge Cases
//
// Tests the formula: preAlertSeconds = min(preAlertWindow, max(secondsUntil, 30))
// where preAlertWindow = 300 (5 minutes)
// These verify boundary conditions that affect whether the AlarmKit schedule
// time ends up in the past (alarm < 30s away) or is correctly capped.

struct PreAlertComputationTests {

    /// Mirrors AlarmSchedulingService.preAlertWindow
    private let preAlertWindow: TimeInterval = 5 * 60

    /// Mirrors the formula at AlarmSchedulingService.swift:272
    private func computePreAlert(secondsUntil: TimeInterval) -> TimeInterval {
        min(preAlertWindow, max(secondsUntil, 30))
    }

    @Test("secondsUntil = 10 → preAlert clamped to floor of 30s, schedule is in the past")
    func alarmLessThan30sAway() {
        let secondsUntil: TimeInterval = 10
        let preAlert = computePreAlert(secondsUntil: secondsUntil)

        #expect(preAlert == 30) // floor clamp
        // Schedule = time - preAlert = (now+10) - 30 = now-20 (in the past!)
        let scheduleOffset = secondsUntil - preAlert
        #expect(scheduleOffset < 0, "Schedule is in the past when alarm is < 30s away")
    }

    @Test("secondsUntil = 30 → preAlert exactly at floor boundary")
    func alarmExactly30sAway() {
        let preAlert = computePreAlert(secondsUntil: 30)
        #expect(preAlert == 30)
    }

    @Test("secondsUntil = 150 → preAlert passes through mid-range unchanged")
    func alarmMidRange() {
        let preAlert = computePreAlert(secondsUntil: 150)
        #expect(preAlert == 150)
    }

    @Test("secondsUntil = 300 → preAlert exactly at cap boundary")
    func alarmExactly5MinAway() {
        let preAlert = computePreAlert(secondsUntil: 300)
        #expect(preAlert == 300)
    }

    @Test("secondsUntil = 600 → preAlert capped at 300 (5 min window)")
    func alarm10MinAway() {
        let preAlert = computePreAlert(secondsUntil: 600)
        #expect(preAlert == 300, "Should cap at preAlertWindow")
    }

    @Test("secondsUntil = 3600 → preAlert capped at 300 for any large value")
    func alarm1HourAway() {
        let preAlert = computePreAlert(secondsUntil: 3600)
        #expect(preAlert == 300)
    }

    @Test("secondsUntil = -5 → negative clamped to floor of 30s")
    func alarmInThePast() {
        let preAlert = computePreAlert(secondsUntil: -5)
        #expect(preAlert == 30, "Negative secondsUntil should clamp to floor")
    }

    @Test("secondsUntil = 0 → exactly at prayer time, clamped to 30s")
    func alarmExactlyNow() {
        let preAlert = computePreAlert(secondsUntil: 0)
        #expect(preAlert == 30)
    }

    @Test("Schedule offset: preAlert < secondsUntil → schedule is in the future")
    func scheduleInFuture() {
        let secondsUntil: TimeInterval = 600 // 10 min
        let preAlert = computePreAlert(secondsUntil: secondsUntil) // 300
        let scheduleOffset = secondsUntil - preAlert
        #expect(scheduleOffset > 0, "Schedule should be in the future")
        #expect(scheduleOffset == 300)
    }

    @Test("Schedule offset: preAlert == secondsUntil → schedule fires immediately (now)")
    func scheduleNow() {
        let secondsUntil: TimeInterval = 150
        let preAlert = computePreAlert(secondsUntil: secondsUntil) // 150
        let scheduleOffset = secondsUntil - preAlert
        #expect(scheduleOffset == 0, "Schedule fires exactly now")
    }
}

// MARK: - Offset + PreAlert Independence Tests
//
// User offsets shift WHEN the alarm fires. PreAlert shifts WHEN the LA appears.
// These are independent: offset shifts scheduledTime, preAlert shifts the AlarmKit schedule.

struct OffsetPreAlertIndependenceTests {

    private let preAlertWindow: TimeInterval = 300

    @Test("Negative offset shifts fire time backward, preAlert is independent")
    func negativeOffsetIndependence() {
        let prayerTime = Date().addingTimeInterval(3600) // 1 hour from now
        let offsetMinutes = -30

        // Step 1: Apply user offset (reconcileAlarms logic)
        let scheduledTime = prayerTime.addingTimeInterval(TimeInterval(offsetMinutes * 60))
        #expect(scheduledTime == prayerTime.addingTimeInterval(-1800))

        // Step 2: Compute preAlert (scheduleAlarm logic)
        let secondsUntil = scheduledTime.timeIntervalSince(.now)
        let preAlert = min(preAlertWindow, max(secondsUntil, 30))
        #expect(preAlert == 300, "preAlert capped at 5 min regardless of offset")

        // Step 3: AlarmKit schedule time
        let alarmKitSchedule = scheduledTime.addingTimeInterval(-preAlert)
        #expect(alarmKitSchedule < scheduledTime)
        #expect(scheduledTime.timeIntervalSince(alarmKitSchedule) == 300)
    }

    @Test("Positive offset shifts fire time forward, preAlert is independent")
    func positiveOffsetIndependence() {
        let prayerTime = Date().addingTimeInterval(3600)
        let offsetMinutes = 15

        let scheduledTime = prayerTime.addingTimeInterval(TimeInterval(offsetMinutes * 60))
        #expect(scheduledTime > prayerTime)

        let secondsUntil = scheduledTime.timeIntervalSince(.now)
        let preAlert = min(preAlertWindow, max(secondsUntil, 30))
        #expect(preAlert == 300, "preAlert always capped for distant alarms")
    }

    @Test("Fajr sunrise offset with nil sunrise falls back to Fajr time")
    func sunriseNilFallback() {
        let entry = DailyPrayerTimes()
        let fajrTime = Date().addingTimeInterval(3600)
        entry.fajr = fajrTime
        // sunrise is nil (extreme latitude / polar region)

        let config = PrayerAlarmConfig(prayer: .fajr)
        config.usesSunriseOffset = true
        config.offsetMinutes = -30

        // Simulate reconcileAlarms logic:
        // if prayer == .fajr, config.usesSunriseOffset, let sunrise = prayerTimes.sunrise
        // → sunrise is nil, falls through to baseTime
        let referenceTime: Date
        if config.usesSunriseOffset, let sunrise = entry.sunrise {
            referenceTime = sunrise
        } else {
            referenceTime = entry.time(for: .fajr)!
        }

        let scheduledTime = referenceTime.addingTimeInterval(TimeInterval(config.offsetMinutes * 60))
        #expect(referenceTime == fajrTime, "Should fall back to Fajr time when sunrise is nil")
        #expect(scheduledTime == fajrTime.addingTimeInterval(-1800))
    }

    @Test("Fajr sunrise offset uses sunrise when available")
    func sunriseOffsetUsed() {
        let entry = DailyPrayerTimes()
        let fajrTime = Date().addingTimeInterval(3600)
        let sunriseTime = Date().addingTimeInterval(3600 + 5400) // 90 min after fajr
        entry.fajr = fajrTime
        entry.sunrise = sunriseTime

        let config = PrayerAlarmConfig(prayer: .fajr)
        config.usesSunriseOffset = true
        config.offsetMinutes = -30

        let referenceTime: Date
        if config.usesSunriseOffset, let sunrise = entry.sunrise {
            referenceTime = sunrise
        } else {
            referenceTime = entry.time(for: .fajr)!
        }

        let scheduledTime = referenceTime.addingTimeInterval(TimeInterval(config.offsetMinutes * 60))
        #expect(referenceTime == sunriseTime, "Should use sunrise as reference")
        #expect(scheduledTime == sunriseTime.addingTimeInterval(-1800))
    }
}

// MARK: - Recovery Alarm Boundary Tests
//
// Tests the 4-hour recovery window: elapsed > 0, elapsed < 4 * 3600

struct RecoveryAlarmBoundaryTests {

    private let recoveryWindow: TimeInterval = 4 * 3600 // 4 hours

    /// Simulates the recovery guard logic from PrayerTimesViewModel.recoverMissedAlarmIfNeeded()
    private func shouldRecover(elapsed: TimeInterval, isCompleted: Bool, hasActiveAlarm: Bool, alreadyRecovered: Bool) -> Bool {
        elapsed > 0 && elapsed < recoveryWindow && !isCompleted && !alreadyRecovered && !hasActiveAlarm
    }

    @Test("Fire date 3h59m ago → recovery schedules")
    func justInsideWindow() {
        let elapsed: TimeInterval = 3 * 3600 + 59 * 60 // 3h 59m
        #expect(shouldRecover(elapsed: elapsed, isCompleted: false, hasActiveAlarm: false, alreadyRecovered: false))
    }

    @Test("Fire date exactly 4h ago → recovery does NOT schedule (boundary)")
    func exactlyAtBoundary() {
        let elapsed: TimeInterval = 4 * 3600
        #expect(!shouldRecover(elapsed: elapsed, isCompleted: false, hasActiveAlarm: false, alreadyRecovered: false),
               "elapsed < 4h check fails at exact boundary")
    }

    @Test("Fire date 4h01m ago → recovery does NOT schedule")
    func justOutsideWindow() {
        let elapsed: TimeInterval = 4 * 3600 + 60
        #expect(!shouldRecover(elapsed: elapsed, isCompleted: false, hasActiveAlarm: false, alreadyRecovered: false))
    }

    @Test("Fire date 1 second ago → recovery schedules")
    func justFired() {
        let elapsed: TimeInterval = 1
        #expect(shouldRecover(elapsed: elapsed, isCompleted: false, hasActiveAlarm: false, alreadyRecovered: false))
    }

    @Test("Fire date in the future (elapsed < 0) → no recovery")
    func futureFireDate() {
        let elapsed: TimeInterval = -60
        #expect(!shouldRecover(elapsed: elapsed, isCompleted: false, hasActiveAlarm: false, alreadyRecovered: false))
    }

    @Test("Completed prayer → no recovery even within window")
    func completedPrayerSkipsRecovery() {
        let elapsed: TimeInterval = 1800
        #expect(!shouldRecover(elapsed: elapsed, isCompleted: true, hasActiveAlarm: false, alreadyRecovered: false))
    }

    @Test("Active alarm exists → no recovery (prevents duplicate)")
    func activeAlarmSkipsRecovery() {
        let elapsed: TimeInterval = 1800
        #expect(!shouldRecover(elapsed: elapsed, isCompleted: false, hasActiveAlarm: true, alreadyRecovered: false))
    }

    @Test("Already recovered this session → no duplicate recovery")
    func alreadyRecoveredSkips() {
        let elapsed: TimeInterval = 1800
        #expect(!shouldRecover(elapsed: elapsed, isCompleted: false, hasActiveAlarm: false, alreadyRecovered: true))
    }
}

// MARK: - PrayerAlarmMetadata Tests

struct PrayerAlarmMetadataTests {

    @Test("Default init creates valid metadata with empty values")
    func defaultInit() {
        let metadata = PrayerAlarmMetadata()
        #expect(metadata.prayerName == "")
        #expect(metadata.preAlertSeconds == 300)
        #expect(metadata.snoozeDurationSeconds == 300)
    }

    @Test("Convenience init populates all fields")
    func convenienceInit() {
        let fireDate = Date().addingTimeInterval(300)
        let metadata = PrayerAlarmMetadata(
            prayer: .fajr,
            fireDate: fireDate,
            nextPrayer: .dhuhr,
            nextPrayerTimeString: "12:30 PM",
            snoozeDurationSeconds: 120,
            preAlertSeconds: 250
        )

        #expect(metadata.prayerName == "fajr")
        #expect(metadata.fireDate == fireDate)
        #expect(metadata.nextPrayerName == "dhuhr")
        #expect(metadata.nextPrayerTimeString == "12:30 PM")
        #expect(metadata.snoozeDurationSeconds == 120)
        #expect(metadata.preAlertSeconds == 250)
    }

    @Test("Post-alert detection: Date.now >= fireDate when fire date is in the past")
    func postAlertDetectionPast() {
        let fireDate = Date().addingTimeInterval(-60) // 1 minute ago
        let metadata = PrayerAlarmMetadata(
            prayer: .fajr,
            fireDate: fireDate,
            snoozeDurationSeconds: 120,
            preAlertSeconds: 300
        )
        #expect(Date.now >= metadata.fireDate, "Past fire date → post-alert")
    }

    @Test("Post-alert detection: Date.now < fireDate when fire date is in the future")
    func postAlertDetectionFuture() {
        let fireDate = Date().addingTimeInterval(300) // 5 min from now
        let metadata = PrayerAlarmMetadata(
            prayer: .fajr,
            fireDate: fireDate,
            snoozeDurationSeconds: 120,
            preAlertSeconds: 300
        )
        #expect(Date.now < metadata.fireDate, "Future fire date → pre-alert")
    }

    @Test("Recovery alarm metadata: fireDate in past + preAlert 4h → silent LA pattern")
    func recoveryAlarmMetadataPattern() {
        let originalFireDate = Date().addingTimeInterval(-1800) // 30 min ago
        let metadata = PrayerAlarmMetadata(
            prayer: .fajr,
            fireDate: originalFireDate,
            snoozeDurationSeconds: 120,
            preAlertSeconds: 4 * 3600 // 4 hours — the silent alarm trick
        )

        // Post-alert check: fireDate is in the past → shows "Pray Now"
        #expect(Date.now >= metadata.fireDate, "Recovery alarm is always post-alert")
        // preAlertSeconds is much larger than any real countdown — keeps LA in countdown mode
        #expect(metadata.preAlertSeconds == 14400)
    }
}

// MARK: - Reconcile Loop Proximity Tests
//
// Tests behavior when two prayers are very close together.

struct PrayerProximityTests {

    @Test("Two prayers 3 minutes apart both get scheduled")
    func prayersCloseTogther() {
        let entry = DailyPrayerTimes()
        let base = Date().addingTimeInterval(3600)

        entry.fajr = base
        entry.dhuhr = base.addingTimeInterval(3600 * 5)
        entry.asr = base.addingTimeInterval(3600 * 8)
        // Maghrib and Isha only 3 minutes apart (extreme latitude)
        entry.maghrib = base.addingTimeInterval(3600 * 11)
        entry.isha = base.addingTimeInterval(3600 * 11 + 180) // 3 min after Maghrib

        let configs = Prayer.allCases.map { PrayerAlarmConfig(prayer: $0) }

        var toSchedule: [(Prayer, Date)] = []

        for prayer in Prayer.allCases {
            guard let config = configs.first(where: { $0.prayerName == prayer.rawValue }),
                  config.isEnabled,
                  let baseTime = entry.time(for: prayer) else { continue }

            let scheduledTime = baseTime.addingTimeInterval(TimeInterval(config.offsetMinutes * 60))
            guard scheduledTime > Date.now else { continue }

            toSchedule.append((prayer, scheduledTime))
        }

        #expect(toSchedule.count == 5, "All 5 prayers scheduled even when close together")

        // Verify Maghrib and Isha are only 3 min apart
        let maghribTime = toSchedule.first(where: { $0.0 == .maghrib })!.1
        let ishaTime = toSchedule.first(where: { $0.0 == .isha })!.1
        #expect(ishaTime.timeIntervalSince(maghribTime) == 180)
    }

    @Test("Large negative offset can make a prayer's scheduled time earlier than previous prayer")
    func offsetCausesOverlap() {
        let entry = DailyPrayerTimes()
        let base = Date().addingTimeInterval(3600)

        entry.fajr = base
        entry.dhuhr = base.addingTimeInterval(3600 * 5)
        entry.asr = base.addingTimeInterval(3600 * 8)
        entry.maghrib = base.addingTimeInterval(3600 * 11)
        entry.isha = base.addingTimeInterval(3600 * 12)

        let configs = Prayer.allCases.map { PrayerAlarmConfig(prayer: $0) }
        // Set Isha offset to -90 minutes → fires 30 min before Maghrib
        configs.first(where: { $0.prayerName == "isha" })?.offsetMinutes = -90

        let maghribScheduled = entry.time(for: .maghrib)!
        let ishaScheduled = entry.time(for: .isha)!.addingTimeInterval(-90 * 60)

        #expect(ishaScheduled < maghribScheduled,
               "Isha with -90 offset fires before Maghrib — edge case")
    }
}

// MARK: - CustomReminder Model Tests

struct CustomReminderTests {

    @Test("Default init has correct initial values")
    func defaultInit() {
        let reminder = CustomReminder()

        #expect(reminder.title == "")
        #expect(reminder.notes == "")
        #expect(reminder.scheduledTime == nil)
        #expect(reminder.isRecurring == false)
        #expect(reminder.recurrenceDays.isEmpty)
        #expect(reminder.soundFileName == "default_reminder")
        #expect(reminder.isEnabled == true)
        #expect(reminder.snoozeDurationSeconds == 300)
        #expect(reminder.calendarEventID == nil)
    }

    @Test("Recurrence days accept valid day-of-week numbers")
    func recurrenceDays() {
        let reminder = CustomReminder()
        reminder.isRecurring = true
        reminder.recurrenceDays = [1, 3, 5, 7] // Sun, Tue, Thu, Sat

        #expect(reminder.recurrenceDays.count == 4)
        #expect(reminder.recurrenceDays.allSatisfy { (1...7).contains($0) })
    }
}

// MARK: - UserPreferences Alarm-Related Tests

struct UserPreferencesAlarmTests {

    @Test("Default calculation method is ISNA")
    func defaultMethod() {
        let prefs = UserPreferences()
        #expect(prefs.calculationMethod == .isna)
    }

    @Test("Default school is Shafi")
    func defaultSchool() {
        let prefs = UserPreferences()
        #expect(prefs.school == .shafi)
    }

    @Test("Setting calculation method updates raw value")
    func setCalculationMethod() {
        let prefs = UserPreferences()
        prefs.calculationMethod = .mwl
        #expect(prefs.calculationMethodRaw == CalculationMethod.mwl.rawValue)
        #expect(prefs.calculationMethod == .mwl)
    }

    @Test("Setting school updates raw value")
    func setSchool() {
        let prefs = UserPreferences()
        prefs.school = .hanafi
        #expect(prefs.schoolRaw == AsrSchool.hanafi.rawValue)
        #expect(prefs.school == .hanafi)
    }

    @Test("Invalid raw value falls back to ISNA")
    func invalidMethodRawValueFallback() {
        let prefs = UserPreferences()
        prefs.calculationMethodRaw = 999
        #expect(prefs.calculationMethod == .isna)
    }

    @Test("Invalid school raw value falls back to Shafi")
    func invalidSchoolRawValueFallback() {
        let prefs = UserPreferences()
        prefs.schoolRaw = 999
        #expect(prefs.school == .shafi)
    }
}
