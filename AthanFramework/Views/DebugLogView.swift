// DEBUG: entire file — remove when debugging complete
import SwiftUI

struct DebugLogView: View {
    private var log = DebugLog.shared

    var body: some View {
        List(log.entries.reversed()) { entry in
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(entry.message)
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(entry.isError ? .red : .primary)
            }
        }
        .navigationTitle("Debug Log")
        .toolbar {
            Button("Clear") { log.clear() }
        }
    }
}
