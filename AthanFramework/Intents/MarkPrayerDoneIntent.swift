import AppIntents
import AlarmKit

/// Intent fired when the user taps the "Done" (stop) button on a prayer alarm.
/// Cancels the alarm so it stops ringing / snoozing. Conforms to `LiveActivityIntent`
/// because AlarmKit requires it for alarm button actions.
public struct MarkPrayerDoneIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource { "Mark Prayer Done" }
    public static var description: IntentDescription { IntentDescription("Dismisses the prayer alarm") }
    public static var openAppWhenRun: Bool { false }

    @Parameter(title: "Alarm Identifier")
    public var alarmIdentifier: String

    @Parameter(title: "Prayer Name")
    public var prayerName: String

    public init() {
        self.alarmIdentifier = ""
        self.prayerName = ""
    }

    public init(alarmIdentifier: String, prayerName: String) {
        self.alarmIdentifier = alarmIdentifier
        self.prayerName = prayerName
    }

    public func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmIdentifier) else {
            print("[AlarmKit] MarkPrayerDone: invalid alarm ID '\(alarmIdentifier)'")
            return .result()
        }
        do {
            try AlarmManager.shared.stop(id: id)
            print("[AlarmKit] MarkPrayerDone: stopped alarm \(id) for \(prayerName)")
        } catch {
            print("[AlarmKit] MarkPrayerDone: failed to stop alarm \(id): \(error)")
        }
        return .result()
    }
}
