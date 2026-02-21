import AppIntents
import ActivityKit

/// Marks a prayer as done from the standalone "Pray Now" Live Activity.
/// Writes completion to App Group and ends the ActivityKit Live Activity.
/// This intent does NOT interact with AlarmKit at all.
struct MarkPrayerDoneIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Mark Prayer Done" }
    static var description: IntentDescription { IntentDescription("Marks the prayer as done and dismisses the Pray Now widget") }

    @Parameter(title: "Prayer Name")
    var prayerName: String

    init() {
        self.prayerName = ""
    }

    init(prayerName: String) {
        self.prayerName = prayerName
    }

    func perform() async throws -> some IntentResult {
        logPrayNowIntent("MarkDone: \(prayerName)")

        guard !prayerName.isEmpty else { return .result() }

        // Write completion to App Group so the main app picks it up
        if let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) {
            var completed = suite.dictionary(forKey: AppConstants.AppGroup.completedKey) as? [String: Double] ?? [:]
            completed[prayerName] = Date().timeIntervalSince1970
            suite.set(completed, forKey: AppConstants.AppGroup.completedKey)
            logPrayNowIntent("MarkDone: wrote completion for \(prayerName)")
        }

        // End all PrayNow activities matching this prayer
        for activity in Activity<PrayNowAttributes>.activities {
            if activity.attributes.prayerName == prayerName {
                let finalState = PrayNowAttributes.ContentState(isActive: false)
                await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
                logPrayNowIntent("MarkDone: ended activity \(activity.id)")
            }
        }

        // Also stop any AlarmKit alarms for this prayer (via App Group flag)
        // The main app will pick this up on foreground and cancel the alarm
        if let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) {
            // Cancel followup alarm if one exists
            let followupKey = AppConstants.AppGroup.followupAlarmIDKey(for: prayerName)
            suite.removeObject(forKey: followupKey)

            // Clean up fired alarms tracking
            var firedAlarms = suite.dictionary(forKey: AppConstants.AppGroup.firedAlarmsKey) as? [String: Double] ?? [:]
            firedAlarms.removeValue(forKey: prayerName)
            suite.set(firedAlarms, forKey: AppConstants.AppGroup.firedAlarmsKey)
        }

        return .result()
    }
}

/// Writes intent actions to App Group for debug visibility in the main app.
private func logPrayNowIntent(_ message: String) {
    print("[PrayNow] \(message)")
    guard let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) else { return }
    var logs = suite.stringArray(forKey: "intentLogs") ?? []
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    logs.append("[\(timestamp)] PrayNow: \(message)")
    if logs.count > 50 { logs = Array(logs.suffix(50)) }
    suite.set(logs, forKey: "intentLogs")
}
