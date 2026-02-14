import SwiftUI
import WidgetKit
import AlarmKit

/// Live Activity for urgent custom reminder alarms.
struct ReminderAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<ReminderAlarmMetadata>.self) { context in
            // Lock Screen presentation
            let metadata = context.attributes.metadata ?? ReminderAlarmMetadata()
            HStack(spacing: 16) {
                Image(systemName: "bell.badge.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata.reminderTitle)
                        .font(.headline)
                        .foregroundStyle(.white)

                    ReminderCountdownText(state: context.state)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.9))
                }

                Spacer()
            }
            .padding()
            .activityBackgroundTint(.orange.opacity(0.8))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "bell.badge.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.metadata?.reminderTitle ?? "Reminder")
                            .font(.headline)
                            .lineLimit(1)
                        ReminderCountdownText(state: context.state)
                            .font(.subheadline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ReminderCountdownProgress(state: context.state)
                        .frame(width: 36, height: 36)
                }
            } compactLeading: {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                ReminderCountdownText(state: context.state)
                    .font(.caption)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct ReminderCountdownText: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...countdown.fireDate)
                .monospacedDigit()
                .lineLimit(1)
        case .alert:
            Text("Reminder!")
                .fontWeight(.semibold)
                .foregroundStyle(.red)
        case .paused:
            Text("Paused")
                .foregroundStyle(.secondary)
        @unknown default:
            Text("--:--")
        }
    }
}

struct ReminderCountdownProgress: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            ProgressView(
                timerInterval: Date.now...countdown.fireDate,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .progressViewStyle(.circular)
            .tint(.orange)
        case .alert:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.red)
        case .paused:
            Image(systemName: "pause.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        @unknown default:
            EmptyView()
        }
    }
}
