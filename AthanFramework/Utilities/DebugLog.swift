// DEBUG: entire file — remove when debugging complete
import Foundation

@Observable
@MainActor
final class DebugLog {
    static let shared = DebugLog()
    private(set) var entries: [Entry] = []

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let message: String
        let isError: Bool
    }

    func log(_ message: String) {
        entries.append(Entry(message: message, isError: false))
        print("[DEBUG] \(message)")
    }

    func error(_ message: String) {
        entries.append(Entry(message: message, isError: true))
        print("[DEBUG ERROR] \(message)")
    }

    func clear() { entries.removeAll() }

    /// Imports intent logs from App Group (written by widget extension intents).
    /// Call on foreground return to see what intents did while the app was backgrounded.
    func importIntentLogs() {
        guard let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName) else { return }
        let logs = suite.stringArray(forKey: "intentLogs") ?? []
        for msg in logs {
            entries.append(Entry(message: "INTENT \(msg)", isError: false))
        }
        if !logs.isEmpty {
            suite.removeObject(forKey: "intentLogs")
            print("[DEBUG] Imported \(logs.count) intent log(s)")
        }
    }
}
