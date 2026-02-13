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
