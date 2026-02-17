import AppIntents
import AlarmKit
import SwiftUI

// MARK: - Dismiss (Stop Button on System Alert)

/// Stops the alarm sound but keeps the Live Activity alive.
/// Uses `countdown()` so the LA persists with a count-up timer.
/// Does NOT mark the prayer as done — dismiss ≠ completed.
struct DismissPrayerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Dismiss Prayer Alarm" }
    static var description: IntentDescription { IntentDescription("Dismisses the alarm sound but keeps the Live Activity") }

    @Parameter(title: "Alarm Identifier")
    var alarmID: String

    @Parameter(title: "Entity Name")
    var entityName: String

    init() {
        self.alarmID = ""
        self.entityName = ""
    }

    init(alarmID: String, entityName: String = "") {
        self.alarmID = alarmID
        self.entityName = entityName
    }

    func perform() throws -> some IntentResult {
        guard let uuid = UUID(uuidString: alarmID) else { return .result() }
        // Catch errors to prevent system error dialog
        do {
            try AlarmManager.shared.countdown(id: uuid)
        } catch {
            print("[AlarmKit] Dismiss failed, falling back to stop: \(error)")
            // If countdown fails, try stop as last resort
            try? AlarmManager.shared.stop(id: uuid)
        }
        return .result()
    }
}

// MARK: - Snooze (Secondary Button on System Alert)

/// Keeps the Live Activity alive and schedules a NEW alert-only alarm
/// that re-fires after the prayer's snooze duration.
struct SnoozePrayerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Snooze Prayer Alarm" }
    static var description: IntentDescription { IntentDescription("Snoozes the alarm and schedules a re-fire") }

    @Parameter(title: "Alarm Identifier")
    var alarmID: String

    @Parameter(title: "Entity Name")
    var entityName: String

    init() {
        self.alarmID = ""
        self.entityName = ""
    }

    init(alarmID: String, entityName: String = "") {
        self.alarmID = alarmID
        self.entityName = entityName
    }

    func perform() async throws -> some IntentResult {
        // With .countdown secondaryButtonBehavior, AlarmKit handles snooze natively
        // by restarting the countdown with the postAlert duration. This intent is
        // kept for backward compatibility but should not be invoked.
        if let uuid = UUID(uuidString: alarmID) {
            do {
                try AlarmManager.shared.countdown(id: uuid)
            } catch {
                print("[AlarmKit] Snooze countdown fallback failed: \(error)")
            }
        }
        return .result()
    }
}

// MARK: - Mark Done (Widget "Done" Button)

/// Fully stops the alarm + Live Activity and marks the prayer as completed.
/// Uses `stop()` — this is terminal (kills LA permanently).
struct MarkDoneIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Mark Prayer Done" }
    static var description: IntentDescription { IntentDescription("Marks the prayer as done and dismisses the Live Activity") }

    @Parameter(title: "Alarm Identifier")
    var alarmID: String

    @Parameter(title: "Entity Name")
    var entityName: String

    init() {
        self.alarmID = ""
        self.entityName = ""
    }

    init(alarmID: String, entityName: String = "") {
        self.alarmID = alarmID
        self.entityName = entityName
    }

    func perform() throws -> some IntentResult {
        // Write completion to shared App Group UserDefaults
        if !entityName.isEmpty,
           let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) {
            var completed = suite.dictionary(forKey: AppConstants.AppGroup.completedKey) as? [String: Double] ?? [:]
            completed[entityName] = Date().timeIntervalSince1970
            suite.set(completed, forKey: AppConstants.AppGroup.completedKey)
        }

        // stop() kills both the alarm and the Live Activity — terminal action
        if let uuid = UUID(uuidString: alarmID) {
            do {
                try AlarmManager.shared.stop(id: uuid)
            } catch {
                print("[AlarmKit] MarkDone stop failed: \(error)")
                // Try cancel as fallback
                try? AlarmManager.shared.cancel(id: uuid)
            }
        }
        return .result()
    }
}

// MARK: - AlarmButton Presets

extension AlarmButton {
    static var prayerDismissButton: Self {
        AlarmButton(text: "Dismiss", textColor: .white, systemImageName: "xmark.circle.fill")
    }

    static var prayerSnoozeButton: Self {
        AlarmButton(text: "Snooze", textColor: .white, systemImageName: "bell.and.waves.left.and.right.fill")
    }
}
