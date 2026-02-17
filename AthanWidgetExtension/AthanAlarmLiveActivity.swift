import SwiftUI
import WidgetKit
import AlarmKit
import AppIntents

/// Live Activity for prayer alarms — phthalo green theme.
/// Pre-alert: shows "[Prayer] in" + countdown, no Done button.
/// Post-alert: shows "[Prayer] — Pray Now" + Done button.
struct AthanAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<PrayerAlarmMetadata>.self) { context in
            lockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(AthanTheme.liveActivityBg)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeading(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(state: context.state, metadata: context.attributes.metadata)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                compactLeadingView(metadata: context.attributes.metadata)
            } compactTrailing: {
                compactTrailingView(state: context.state, metadata: context.attributes.metadata)
            } minimal: {
                minimalView(state: context.state, metadata: context.attributes.metadata)
            }
            .keylineTint(AthanTheme.accent)
        }
    }

    private func isPostAlert(state: AlarmPresentationState, metadata: PrayerAlarmMetadata?) -> Bool {
        guard let fireDate = metadata?.fireDate else { return false }
        return Date.now >= fireDate
    }

    // MARK: - Lock Screen View

    func lockScreenView(attributes: AlarmAttributes<PrayerAlarmMetadata>, state: AlarmPresentationState) -> some View {
        let postAlert = isPostAlert(state: state, metadata: attributes.metadata)
        let prayerName = attributes.metadata?.prayerName ?? ""
        let prayer = Prayer(rawValue: prayerName)

        return VStack(spacing: 14) {
            // Top: app icon + prayer info + countdown
            HStack(alignment: .center, spacing: 10) {
                LAAppIconView()

                VStack(alignment: .leading, spacing: 2) {
                    if postAlert {
                        Text("\(prayer?.displayName ?? "Prayer") \u{2014} Pray Now")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                    } else {
                        Text("\(prayer?.displayName ?? "Prayer") in")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))

                        Text("Adhan at \(attributes.metadata?.fireDate.formatted(date: .omitted, time: .shortened) ?? "")")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                Spacer()

                timerDisplay(state: state, metadata: attributes.metadata)
                    .font(.system(size: 34, weight: .light))
            }

            // Progress bar
            LAProgressBar(state: state, metadata: attributes.metadata)

            // Bottom row
            HStack {
                if postAlert {
                    Spacer()
                    PrayerAlarmControls(state: state, entityName: prayerName)
                } else {
                    // Show next prayer info (no Done button pre-alert)
                    if let nextName = attributes.metadata?.nextPrayerName,
                       let nextPrayer = Prayer(rawValue: nextName),
                       let nextTimeStr = attributes.metadata?.nextPrayerTimeString,
                       !nextTimeStr.isEmpty {
                        (Text("\(nextPrayer.displayName) at ")
                            .foregroundStyle(.white.opacity(0.35))
                         + Text(nextTimeStr)
                            .foregroundStyle(.white.opacity(0.55)))
                        .font(.system(size: 13))
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    // MARK: - Timer Display

    func timerDisplay(state: AlarmPresentationState, metadata: PrayerAlarmMetadata?) -> some View {
        Group {
            switch state.mode {
            case .countdown(let countdown):
                if let fireDate = metadata?.fireDate, Date.now >= fireDate {
                    Text(fireDate, style: .timer)
                        .foregroundStyle(.red)
                } else {
                    Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
                }
            case .paused(let pausedState):
                let remaining = Duration.seconds(pausedState.totalCountdownDuration - pausedState.previouslyElapsedDuration)
                let pattern: Duration.TimeFormatStyle.Pattern = remaining > .seconds(60 * 60) ? .hourMinuteSecond : .minuteSecond
                Text(remaining.formatted(.time(pattern: pattern)))
            case .alert:
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
    }

    // MARK: - Dynamic Island Expanded

    @ViewBuilder
    func expandedLeading(attributes: AlarmAttributes<PrayerAlarmMetadata>, state: AlarmPresentationState) -> some View {
        let postAlert = isPostAlert(state: state, metadata: attributes.metadata)
        let prayerName = attributes.metadata?.prayerName ?? ""
        let prayer = Prayer(rawValue: prayerName)

        if postAlert {
            HStack(spacing: 4) {
                if let prayer {
                    Image(systemName: prayer.sfSymbol)
                        .foregroundStyle(AthanTheme.accent)
                }
                Text("\(prayer?.displayName ?? "Prayer") \u{2014} Pray Now")
            }
            .font(.title3)
            .fontWeight(.semibold)
            .lineLimit(1)
            .padding(.leading, 6)
        } else {
            HStack(spacing: 4) {
                if let prayer {
                    Image(systemName: prayer.sfSymbol)
                        .foregroundStyle(AthanTheme.accent)
                }
                Text("\(prayer?.displayName ?? "Prayer") in")
            }
            .font(.title3)
            .fontWeight(.semibold)
            .lineLimit(1)
            .padding(.leading, 6)
        }
    }

    @ViewBuilder
    func expandedTrailing(state: AlarmPresentationState, metadata: PrayerAlarmMetadata?) -> some View {
        timerDisplay(state: state, metadata: metadata)
            .font(.title3)
            .fontWeight(.medium)
            .padding(.trailing, 6)
    }

    func expandedBottom(attributes: AlarmAttributes<PrayerAlarmMetadata>, state: AlarmPresentationState) -> some View {
        let postAlert = isPostAlert(state: state, metadata: attributes.metadata)
        let prayerName = attributes.metadata?.prayerName ?? ""

        return HStack {
            if postAlert {
                Spacer()
                PrayerAlarmControls(state: state, entityName: prayerName)
            } else {
                if let nextName = attributes.metadata?.nextPrayerName,
                   let nextPrayer = Prayer(rawValue: nextName),
                   let nextTimeStr = attributes.metadata?.nextPrayerTimeString,
                   !nextTimeStr.isEmpty {
                    Text("\(nextPrayer.displayName) at \(nextTimeStr)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Dynamic Island Compact

    @ViewBuilder
    func compactLeadingView(metadata: PrayerAlarmMetadata?) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AthanTheme.accent.opacity(0.9), AthanTheme.accentDeep.opacity(0.6)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 5
                    )
                )
                .frame(width: 10, height: 10)

            if let prayerName = metadata?.prayerName,
               let prayer = Prayer(rawValue: prayerName) {
                Text(prayer.displayName)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    func compactTrailingView(state: AlarmPresentationState, metadata: PrayerAlarmMetadata?) -> some View {
        let postAlert: Bool = {
            guard let fireDate = metadata?.fireDate else { return false }
            return Date.now >= fireDate
        }()

        if postAlert {
            PrayerAlarmProgressView(
                metadata: metadata,
                mode: state.mode,
                isPostAlert: true,
                tint: AthanTheme.accent
            )
        } else {
            timerDisplay(state: state, metadata: metadata)
                .font(.caption2)
                .foregroundStyle(AthanTheme.accent)
                .frame(maxWidth: 44)
        }
    }

    // MARK: - Minimal

    @ViewBuilder
    func minimalView(state: AlarmPresentationState, metadata: PrayerAlarmMetadata?) -> some View {
        let postAlert: Bool = {
            guard let fireDate = metadata?.fireDate else { return false }
            return Date.now >= fireDate
        }()

        PrayerAlarmProgressView(
            metadata: metadata,
            mode: state.mode,
            isPostAlert: postAlert,
            tint: AthanTheme.accent
        )
    }
}

// MARK: - LA App Icon

private struct LAAppIconView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(
                LinearGradient(
                    colors: [Color(hex: "#0a2e2a"), Color(hex: "#051a17")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 28, height: 28)
            .overlay {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [AthanTheme.accent.opacity(0.9), AthanTheme.accentDeep.opacity(0.5)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 5
                            )
                        )
                        .frame(width: 10, height: 10)
                        .offset(y: -3)
                        .shadow(color: AthanTheme.accent.opacity(0.4), radius: 4)

                    Rectangle()
                        .fill(AthanTheme.accent.opacity(0.4))
                        .frame(width: 18, height: 1)
                        .offset(y: 4)
                }
            }
    }
}

// MARK: - LA Progress Bar

private struct LAProgressBar: View {
    var state: AlarmPresentationState
    var metadata: PrayerAlarmMetadata?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.08))

                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [AthanTheme.accent, AthanTheme.accentDeep],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * CGFloat(progress)))
            }
        }
        .frame(height: 4)
    }

    private var progress: Double {
        switch state.mode {
        case .countdown(let countdown):
            let remaining = countdown.fireDate.timeIntervalSince(Date.now)
            // Assume 5 minute pre-alert window
            let total: Double = 300
            let elapsed = total - remaining
            return min(max(elapsed / total, 0), 1)
        case .alert:
            return 1.0
        case .paused(let pausedState):
            let total = pausedState.totalCountdownDuration
            let elapsed = pausedState.previouslyElapsedDuration
            return total > 0 ? min(elapsed / total, 1) : 0
        @unknown default:
            return 0
        }
    }
}

// MARK: - Progress View (Dynamic Island)

struct PrayerAlarmProgressView: View {
    var metadata: PrayerAlarmMetadata?
    var mode: AlarmPresentationState.Mode
    var isPostAlert: Bool
    var tint: Color

    var body: some View {
        Group {
            if isPostAlert {
                if let prayerName = metadata?.prayerName,
                   let prayer = Prayer(rawValue: prayerName) {
                    Image(systemName: prayer.sfSymbol)
                        .foregroundStyle(Color(hex: prayer.colorHex))
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
    var state: AlarmPresentationState
    var entityName: String = ""

    var body: some View {
        HStack(spacing: 8) {
            PrayerButtonView(
                config: .init(text: "Done", textColor: .white, systemImageName: "checkmark.circle.fill"),
                intent: MarkDoneIntent(alarmID: state.alarmID.uuidString, entityName: entityName),
                tint: AthanTheme.accent
            )
        }
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
