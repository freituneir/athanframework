import SwiftUI
import WidgetKit
import AlarmKit

/// Live Activity for prayer alarms — shows on lock screen and Dynamic Island.
struct AthanAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<PrayerAlarmMetadata>.self) { context in
            // Lock Screen / StandBy presentation
            let metadata = context.attributes.metadata ?? PrayerAlarmMetadata()
            LockScreenPrayerView(state: context.state, metadata: metadata)
                .activityBackgroundTint(Color(hex: AppConstants.Defaults.tintColorHex).opacity(0.8))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    if let prayerName = context.attributes.metadata?.prayerName,
                       let prayer = Prayer(rawValue: prayerName) {
                        Image(systemName: prayer.sfSymbol)
                            .font(.title2)
                            .foregroundStyle(Color(hex: prayer.colorHex))
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        if let prayerName = context.attributes.metadata?.prayerName,
                           let prayer = Prayer(rawValue: prayerName) {
                            Text("\(prayer.displayName) Prayer")
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        PrayerCountdownText(state: context.state)
                            .font(.subheadline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PrayerCountdownProgress(state: context.state)
                        .frame(width: 36, height: 36)
                }
            } compactLeading: {
                if let prayerName = context.attributes.metadata?.prayerName,
                   let prayer = Prayer(rawValue: prayerName) {
                    Image(systemName: prayer.sfSymbol)
                        .foregroundStyle(Color(hex: prayer.colorHex))
                }
            } compactTrailing: {
                PrayerCountdownText(state: context.state)
                    .font(.caption)
                    .monospacedDigit()
            } minimal: {
                PrayerCountdownProgress(state: context.state)
            }
        }
    }
}

// MARK: - Lock Screen View

struct LockScreenPrayerView: View {
    let state: AlarmPresentationState
    let metadata: PrayerAlarmMetadata

    var body: some View {
        HStack(spacing: 16) {
            if let prayer = Prayer(rawValue: metadata.prayerName) {
                Image(systemName: prayer.sfSymbol)
                    .font(.largeTitle)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let prayer = Prayer(rawValue: metadata.prayerName) {
                    Text("\(prayer.displayName) Prayer")
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                PrayerCountdownText(state: state)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer()

            PrayerCountdownProgress(state: state)
                .frame(width: 48, height: 48)
        }
        .padding()
    }
}

// MARK: - Countdown Components

struct PrayerCountdownText: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...countdown.fireDate)
                .monospacedDigit()
                .lineLimit(1)
        case .alert:
            Text("Time to pray")
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

struct PrayerCountdownProgress: View {
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
            .tint(.white)
        case .alert:
            Image(systemName: "bell.and.waves.left.and.right.fill")
                .font(.title3)
                .foregroundStyle(.red)
                .symbolEffect(.variableColor.iterative)
        case .paused:
            Image(systemName: "pause.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        @unknown default:
            EmptyView()
        }
    }
}
