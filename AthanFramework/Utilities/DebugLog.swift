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
}
