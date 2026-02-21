import AppIntents
import AlarmKit
import SwiftUI

// MARK: - Intent Logging

/// Writes intent actions to App Group so the main app's Debug Log can display them.
/// Intents run in the widget extension process — print() is invisible to the app.
private func logIntent(_ message: String) {
    print("[AlarmKit] \(message)")
    guard let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) else { return }
    var logs = suite.stringArray(forKey: "intentLogs") ?? []
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    logs.append("[\(timestamp)] \(message)")
    // Keep last 50 entries
    if logs.count > 50 { logs = Array(logs.suffix(50)) }
    suite.set(logs, forKey: "intentLogs")
}

// MARK: - Dismiss (Stop Button on System Alert)

/// Dismisses the alarm and immediately schedules a silent followup "Pray Now" LA.
/// We don't rely solely on countdown() because AlarmKit may kill the LA on dismiss.
/// The followup guarantees a persistent "Pray Now" LA exists until the user taps Done.
struct DismissPrayerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Dismiss Prayer Alarm" }
    static var description: IntentDescription { IntentDescription("Dismisses the alarm sound and shows Pray Now") }

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
        logIntent("Dismiss: \(entityName), alarmID=\(alarmID)")
        // countdown() keeps the AlarmKit LA alive for snooze cycling.
        // The standalone "Pray Now" ActivityKit LA handles persistent lock screen presence
        // independently — we don't need to schedule anything here.
        if let uuid = UUID(uuidString: alarmID) {
            do {
                try AlarmManager.shared.countdown(id: uuid)
                logIntent("Dismiss: countdown() succeeded")
            } catch {
                logIntent("Dismiss: countdown() failed: \(error) — standalone Pray Now LA covers this")
            }
        }
        return .result()
    }
}

// MARK: - Snooze (Secondary Button on System Alert)

/// AlarmKit handles snooze natively via .countdown secondaryButtonBehavior.
/// countdown() keeps the same LA alive and restarts the countdown for postAlert seconds.
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

    func perform() throws -> some IntentResult {
        logIntent("Snooze: \(entityName), alarmID=\(alarmID)")
        if let uuid = UUID(uuidString: alarmID) {
            do {
                try AlarmManager.shared.countdown(id: uuid)
                logIntent("Snooze: countdown() succeeded — re-fires after postAlert")
            } catch {
                logIntent("Snooze: countdown() failed: \(error)")
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
        print("[AlarmKit] MarkDone: \(entityName), alarmID=\(alarmID)")

        // Write completion to shared App Group UserDefaults
        if !entityName.isEmpty,
           let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) {
            var completed = suite.dictionary(forKey: AppConstants.AppGroup.completedKey) as? [String: Double] ?? [:]
            completed[entityName] = Date().timeIntervalSince1970
            suite.set(completed, forKey: AppConstants.AppGroup.completedKey)

            // Cancel the followup alarm for this prayer (stored under a separate ID)
            let followupKey = AppConstants.AppGroup.followupAlarmIDKey(for: entityName)
            if let followupIDStr = suite.string(forKey: followupKey),
               let followupUUID = UUID(uuidString: followupIDStr) {
                print("[AlarmKit] MarkDone: cancelling followup \(followupUUID)")
                try? AlarmManager.shared.cancel(id: followupUUID)
                try? AlarmManager.shared.stop(id: followupUUID)
            }
            suite.removeObject(forKey: followupKey)

            // Cancel the reminder alarm for this prayer
            let reminderKey = AppConstants.AppGroup.reminderAlarmIDKey(for: entityName)
            if let reminderIDStr = suite.string(forKey: reminderKey),
               let reminderUUID = UUID(uuidString: reminderIDStr) {
                print("[AlarmKit] MarkDone: cancelling reminder \(reminderUUID)")
                try? AlarmManager.shared.cancel(id: reminderUUID)
                try? AlarmManager.shared.stop(id: reminderUUID)
            }
            suite.removeObject(forKey: reminderKey)
            suite.removeObject(forKey: AppConstants.AppGroup.reminderFireDateKey(for: entityName))

            // Remove from fired alarms dict so recovery doesn't re-trigger
            var firedAlarms = suite.dictionary(forKey: AppConstants.AppGroup.firedAlarmsKey) as? [String: Double] ?? [:]
            firedAlarms.removeValue(forKey: entityName)
            suite.set(firedAlarms, forKey: AppConstants.AppGroup.firedAlarmsKey)
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
