import AppIntents
import AlarmKit

/// Pauses a prayer alarm countdown.
struct PausePrayerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Pause Prayer Alarm" }
    static var description: IntentDescription { IntentDescription("Pauses the prayer alarm countdown") }

    @Parameter(title: "Alarm Identifier")
    var alarmID: String

    init() {
        self.alarmID = ""
    }

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() throws -> some IntentResult {
        try AlarmManager.shared.pause(id: UUID(uuidString: alarmID)!)
        return .result()
    }
}

/// Resumes a paused prayer alarm countdown.
struct ResumePrayerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Resume Prayer Alarm" }
    static var description: IntentDescription { IntentDescription("Resumes the prayer alarm countdown") }

    @Parameter(title: "Alarm Identifier")
    var alarmID: String

    init() {
        self.alarmID = ""
    }

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() throws -> some IntentResult {
        try AlarmManager.shared.resume(id: UUID(uuidString: alarmID)!)
        return .result()
    }
}

/// Repeats (restarts) a prayer alarm countdown after it fires.
struct RepeatPrayerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Repeat Prayer Alarm" }
    static var description: IntentDescription { IntentDescription("Repeats the prayer alarm countdown") }

    @Parameter(title: "Alarm Identifier")
    var alarmID: String

    init() {
        self.alarmID = ""
    }

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() throws -> some IntentResult {
        try AlarmManager.shared.countdown(id: UUID(uuidString: alarmID)!)
        return .result()
    }
}

/// Acknowledges a prayer alarm — stops the sound but keeps the Live Activity alive
/// by transitioning to post-alert countdown. Used as the alarm config's `stopIntent`
/// so that tapping "Done" on the system alarm UI preserves the Live Activity.
struct StopPrayerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Acknowledge Prayer Alarm" }
    static var description: IntentDescription { IntentDescription("Acknowledges the alarm and enters post-alert countdown") }

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
        // Write completion to shared App Group UserDefaults so the app can sync
        if !entityName.isEmpty,
           let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) {
            var completed = suite.dictionary(forKey: AppConstants.AppGroup.completedKey) as? [String: Double] ?? [:]
            completed[entityName] = Date().timeIntervalSince1970
            suite.set(completed, forKey: AppConstants.AppGroup.completedKey)
        }

        // Use countdown() instead of stop() to keep the Live Activity alive.
        // This transitions to the post-alert countdown phase (countdown to next prayer
        // for prayers, count-up for reminders) while stopping the alarm sound.
        try AlarmManager.shared.countdown(id: UUID(uuidString: alarmID)!)
        return .result()
    }
}

/// Fully dismisses the Live Activity from the widget's "Done" button.
/// Marks the prayer/reminder as complete and stops the alarm + Live Activity.
struct DismissAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Dismiss Alarm" }
    static var description: IntentDescription { IntentDescription("Marks done and dismisses the Live Activity") }

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
        // Write completion to shared App Group UserDefaults so the app can sync
        if !entityName.isEmpty,
           let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) {
            var completed = suite.dictionary(forKey: AppConstants.AppGroup.completedKey) as? [String: Double] ?? [:]
            completed[entityName] = Date().timeIntervalSince1970
            suite.set(completed, forKey: AppConstants.AppGroup.completedKey)
        }

        // stop() kills both the alarm and the Live Activity
        try AlarmManager.shared.stop(id: UUID(uuidString: alarmID)!)
        return .result()
    }
}

// MARK: - AlarmButton Presets

extension AlarmButton {
    static var prayerStopButton: Self {
        AlarmButton(text: "Done", textColor: .white, systemImageName: "checkmark.circle.fill")
    }

    static var prayerSnoozeButton: Self {
        AlarmButton(text: "Snooze", textColor: .white, systemImageName: "bell.and.waves.left.and.right.fill")
    }

    static var prayerPauseButton: Self {
        AlarmButton(text: "Pause", textColor: .white, systemImageName: "pause.fill")
    }

    static var prayerResumeButton: Self {
        AlarmButton(text: "Resume", textColor: .white, systemImageName: "play.fill")
    }
}
