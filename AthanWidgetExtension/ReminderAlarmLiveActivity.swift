import SwiftUI
import WidgetKit
import AlarmKit
import AppIntents

/// Live Activity for urgent custom reminder alarms.
struct ReminderAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<ReminderAlarmMetadata>.self) { context in
            // Lock Screen presentation
            reminderLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(.orange.opacity(0.8))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    reminderTitle(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: "bell.badge.fill")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    reminderBottomView(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                reminderTimerDisplay(state: context.state, metadata: context.attributes.metadata, maxWidth: 44)
                    .foregroundStyle(isPostAlert(metadata: context.attributes.metadata) ? .red : .orange)
            } compactTrailing: {
                ReminderAlarmProgressView(
                    mode: context.state.mode,
                    isPostAlert: isPostAlert(metadata: context.attributes.metadata),
                    tint: .orange
                )
            } minimal: {
                ReminderAlarmProgressView(
                    mode: context.state.mode,
                    isPostAlert: isPostAlert(metadata: context.attributes.metadata),
                    tint: .orange
                )
            }
            .keylineTint(.orange)
        }
    }

    private func isPostAlert(metadata: ReminderAlarmMetadata?) -> Bool {
        guard let fireDate = metadata?.fireDate else { return false }
        return Date.now >= fireDate
    }

    func reminderLockScreenView(attributes: AlarmAttributes<ReminderAlarmMetadata>, state: AlarmPresentationState) -> some View {
        VStack {
            HStack(alignment: .top) {
                reminderTitle(attributes: attributes, state: state)
                Spacer()
                Image(systemName: "bell.badge.fill")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.trailing, 6)
            }

            reminderBottomView(attributes: attributes, state: state)
        }
        .padding(.all, 12)
    }

    func reminderBottomView(attributes: AlarmAttributes<ReminderAlarmMetadata>, state: AlarmPresentationState) -> some View {
        HStack {
            reminderTimerDisplay(state: state, metadata: attributes.metadata, maxWidth: 150)
                .font(.system(size: 40, design: .rounded))
            Spacer()
            ReminderAlarmControls(presentation: attributes.presentation, state: state, entityName: attributes.metadata?.entityName ?? "")
        }
    }

    func reminderTimerDisplay(state: AlarmPresentationState, metadata: ReminderAlarmMetadata?, maxWidth: CGFloat = .infinity) -> some View {
        Group {
            switch state.mode {
            case .countdown(let countdown):
                if let fireDate = metadata?.fireDate, Date.now >= fireDate {
                    // Post-alert: count UP from when alarm fired
                    Text(fireDate, style: .timer)
                        .foregroundStyle(.red)
                } else {
                    // Pre-alert: counting down to alarm
                    Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
                }
            case .paused(let pausedState):
                let remaining = Duration.seconds(pausedState.totalCountdownDuration - pausedState.previouslyElapsedDuration)
                let pattern: Duration.TimeFormatStyle.Pattern = remaining > .seconds(60 * 60) ? .hourMinuteSecond : .minuteSecond
                Text(remaining.formatted(.time(pattern: pattern)))
            case .alert:
                if let fireDate = metadata?.fireDate {
                    Text(fireDate, style: .timer)
                        .foregroundStyle(.red)
                } else {
                    Text("Reminder!")
                        .foregroundStyle(.red)
                }
            @unknown default:
                EmptyView()
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    @ViewBuilder func reminderTitle(attributes: AlarmAttributes<ReminderAlarmMetadata>, state: AlarmPresentationState) -> some View {
        let title = attributes.metadata?.reminderTitle ?? "Reminder"
        if isPostAlert(metadata: attributes.metadata) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.red)
                .lineLimit(1)
                .padding(.leading, 6)
        } else {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.leading, 6)
        }
    }
}

// MARK: - Progress View

struct ReminderAlarmProgressView: View {
    var mode: AlarmPresentationState.Mode
    var isPostAlert: Bool
    var tint: Color

    var body: some View {
        Group {
            if isPostAlert {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.variableColor.iterative)
            } else {
                switch mode {
                case .countdown(let countdown):
                    ProgressView(
                        timerInterval: Date.now...countdown.fireDate,
                        countsDown: true,
                        label: { EmptyView() },
                        currentValueLabel: {
                            Image(systemName: "bell.badge.fill")
                                .scaleEffect(0.9)
                        }
                    )
                case .paused(let pausedState):
                    let remaining = pausedState.totalCountdownDuration - pausedState.previouslyElapsedDuration
                    ProgressView(
                        value: remaining,
                        total: pausedState.totalCountdownDuration,
                        label: { EmptyView() },
                        currentValueLabel: {
                            Image(systemName: "pause.fill")
                                .scaleEffect(0.8)
                        }
                    )
                case .alert:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .symbolEffect(.variableColor.iterative)
                @unknown default:
                    EmptyView()
                }
            }
        }
        .progressViewStyle(.circular)
        .foregroundStyle(tint)
        .tint(tint)
    }
}

// MARK: - Interactive Controls

struct ReminderAlarmControls: View {
    var presentation: AlarmPresentation
    var state: AlarmPresentationState
    var entityName: String = ""

    var body: some View {
        PrayerButtonView(
            config: .prayerStopButton,
            intent: DismissAlarmIntent(alarmID: state.alarmID.uuidString, entityName: entityName),
            tint: .red
        )
    }
}
