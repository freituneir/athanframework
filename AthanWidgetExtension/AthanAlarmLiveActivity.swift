import SwiftUI
import WidgetKit
import AlarmKit
import AppIntents

/// Live Activity for prayer alarms — shows on lock screen and Dynamic Island.
struct AthanAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<PrayerAlarmMetadata>.self) { context in
            // Lock Screen / StandBy presentation
            lockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color(hex: AppConstants.Defaults.tintColorHex).opacity(0.8))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    prayerTitle(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    prayerIcon(metadata: context.attributes.metadata)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    bottomView(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                timerDisplay(state: context.state, metadata: context.attributes.metadata, maxWidth: 44)
                    .foregroundStyle(isPostAlert(state: context.state, metadata: context.attributes.metadata)
                        ? Color(hex: nextPrayerColorHex(metadata: context.attributes.metadata))
                        : Color(hex: AppConstants.Defaults.tintColorHex))
            } compactTrailing: {
                PrayerAlarmProgressView(
                    metadata: context.attributes.metadata,
                    mode: context.state.mode,
                    isPostAlert: isPostAlert(state: context.state, metadata: context.attributes.metadata),
                    tint: Color(hex: AppConstants.Defaults.tintColorHex)
                )
            } minimal: {
                PrayerAlarmProgressView(
                    metadata: context.attributes.metadata,
                    mode: context.state.mode,
                    isPostAlert: isPostAlert(state: context.state, metadata: context.attributes.metadata),
                    tint: Color(hex: AppConstants.Defaults.tintColorHex)
                )
            }
            .keylineTint(Color(hex: AppConstants.Defaults.tintColorHex))
        }
    }

    /// Detects whether the alarm has already fired (post-alert phase).
    private func isPostAlert(state: AlarmPresentationState, metadata: PrayerAlarmMetadata?) -> Bool {
        guard let fireDate = metadata?.fireDate else { return false }
        return Date.now >= fireDate
    }

    /// Returns the color hex of the next prayer for post-alert display.
    private func nextPrayerColorHex(metadata: PrayerAlarmMetadata?) -> String {
        guard let name = metadata?.nextPrayerName,
              let prayer = Prayer(rawValue: name) else {
            return AppConstants.Defaults.tintColorHex
        }
        return prayer.colorHex
    }

    func lockScreenView(attributes: AlarmAttributes<PrayerAlarmMetadata>, state: AlarmPresentationState) -> some View {
        VStack {
            HStack(alignment: .top) {
                prayerTitle(attributes: attributes, state: state)
                Spacer()
                prayerIcon(metadata: attributes.metadata)
            }

            bottomView(attributes: attributes, state: state)
        }
        .padding(.all, 12)
    }

    func bottomView(attributes: AlarmAttributes<PrayerAlarmMetadata>, state: AlarmPresentationState) -> some View {
        HStack {
            timerDisplay(state: state, metadata: attributes.metadata, maxWidth: 150)
                .font(.system(size: 40, design: .rounded))
            Spacer()
            PrayerAlarmControls(presentation: attributes.presentation, state: state, entityName: attributes.metadata?.prayerName ?? "")
        }
    }

    func timerDisplay(state: AlarmPresentationState, metadata: PrayerAlarmMetadata?, maxWidth: CGFloat = .infinity) -> some View {
        Group {
            switch state.mode {
            case .countdown(let countdown):
                // Both pre-alert and post-alert use a countdown.
                // Pre-alert: counting down to this prayer's alarm.
                // Post-alert: counting down to the NEXT prayer (postAlert = next prayer interval).
                Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
            case .paused(let pausedState):
                let remaining = Duration.seconds(pausedState.totalCountdownDuration - pausedState.previouslyElapsedDuration)
                let pattern: Duration.TimeFormatStyle.Pattern = remaining > .seconds(60 * 60) ? .hourMinuteSecond : .minuteSecond
                Text(remaining.formatted(.time(pattern: pattern)))
            case .alert:
                // Brief alert state — show prayer name
                if let prayerName = metadata?.prayerName,
                   let prayer = Prayer(rawValue: prayerName) {
                    Text("Time for \(prayer.displayName)")
                        .foregroundStyle(.red)
                } else {
                    Text("Time to pray")
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

    @ViewBuilder func prayerTitle(attributes: AlarmAttributes<PrayerAlarmMetadata>, state: AlarmPresentationState) -> some View {
        if isPostAlert(state: state, metadata: attributes.metadata) {
            // Post-alert: show "Next: [prayer name]" if available
            if let nextName = attributes.metadata?.nextPrayerName,
               let nextPrayer = Prayer(rawValue: nextName) {
                HStack(spacing: 4) {
                    Image(systemName: nextPrayer.sfSymbol)
                        .foregroundStyle(Color(hex: nextPrayer.colorHex))
                    Text("Next: \(nextPrayer.displayName)")
                }
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.leading, 6)
            } else if let prayerName = attributes.metadata?.prayerName,
                      let prayer = Prayer(rawValue: prayerName) {
                Text("Time for \(prayer.displayName)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .padding(.leading, 6)
            } else {
                Text("Time to pray")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .padding(.leading, 6)
            }
        } else {
            let title: LocalizedStringResource? = switch state.mode {
            case .countdown:
                attributes.presentation.countdown?.title
            case .paused:
                attributes.presentation.paused?.title
            default:
                nil
            }

            Text(title ?? "Prayer")
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.leading, 6)
        }
    }

    @ViewBuilder func prayerIcon(metadata: PrayerAlarmMetadata?) -> some View {
        if let prayerName = metadata?.prayerName,
           let prayer = Prayer(rawValue: prayerName) {
            HStack(spacing: 4) {
                Text(prayer.displayName)
                Image(systemName: prayer.sfSymbol)
            }
            .font(.body)
            .fontWeight(.medium)
            .foregroundStyle(Color(hex: prayer.colorHex))
            .lineLimit(1)
            .padding(.trailing, 6)
        } else {
            EmptyView()
        }
    }
}

// MARK: - Progress View

struct PrayerAlarmProgressView: View {
    var metadata: PrayerAlarmMetadata?
    var mode: AlarmPresentationState.Mode
    var isPostAlert: Bool
    var tint: Color

    var body: some View {
        Group {
            if isPostAlert {
                // Post-alert: show next prayer icon
                if let nextName = metadata?.nextPrayerName,
                   let nextPrayer = Prayer(rawValue: nextName) {
                    Image(systemName: nextPrayer.sfSymbol)
                        .foregroundStyle(Color(hex: nextPrayer.colorHex))
                } else {
                    Image(systemName: "bell.and.waves.left.and.right.fill")
                        .foregroundStyle(.red)
                        .symbolEffect(.variableColor.iterative)
                }
            } else {
                switch mode {
                case .countdown(let countdown):
                    ProgressView(
                        timerInterval: Date.now...countdown.fireDate,
                        countsDown: true,
                        label: { EmptyView() },
                        currentValueLabel: {
                            if let prayerName = metadata?.prayerName,
                               let prayer = Prayer(rawValue: prayerName) {
                                Image(systemName: prayer.sfSymbol)
                                    .scaleEffect(0.9)
                            }
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
                    Image(systemName: "bell.and.waves.left.and.right.fill")
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

struct PrayerAlarmControls: View {
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

struct PrayerButtonView<I>: View where I: AppIntent {
    var config: AlarmButton
    var intent: I
    var tint: Color

    init?(config: AlarmButton?, intent: I, tint: Color) {
        guard let config else { return nil }
        self.config = config
        self.intent = intent
        self.tint = tint
    }

    var body: some View {
        Button(intent: intent) {
            Label(config.text, systemImage: config.systemImageName)
                .lineLimit(1)
        }
        .tint(tint)
        .buttonStyle(.borderedProminent)
        .frame(width: 96, height: 30)
    }
}
