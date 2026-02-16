import SwiftUI

/// Debug view showing all alarms currently tracked by AlarmKit on this device.
struct ScheduledAlarmsView: View {
    @Environment(AlarmSchedulingService.self) private var alarmService
    @State private var alarms: [AlarmSchedulingService.AlarmInfo] = []

    var body: some View {
        List {
            ForEach(alarms) { alarm in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(alarm.label.capitalized)
                            .font(.headline)
                        Spacer()
                        Text(alarm.isActive ? "Active" : "Stale")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                alarm.isActive
                                    ? Color.green.opacity(0.15)
                                    : Color.gray.opacity(0.15),
                                in: Capsule()
                            )
                            .foregroundStyle(alarm.isActive ? .green : .secondary)
                    }

                    if let fire = alarm.fireDate {
                        HStack(spacing: 4) {
                            Image(systemName: "alarm.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text("Fires:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(fire, style: .time)
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(fire, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "circle.inset.filled")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            Text("Live Activity:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            let laStart = fire.addingTimeInterval(-AlarmSchedulingService.preAlertWindow)
                            Text(laStart, style: .time)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }

                    Text(alarm.id.uuidString.prefix(8))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospaced()
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Scheduled Alarms")
        .overlay {
            if alarms.isEmpty {
                ContentUnavailableView(
                    "No Alarms",
                    systemImage: "alarm",
                    description: Text("No alarms are currently scheduled.")
                )
            }
        }
        .refreshable { reload() }
        .onAppear { reload() }
    }

    private func reload() {
        alarms = alarmService.fetchAlarmDetails()
    }
}
