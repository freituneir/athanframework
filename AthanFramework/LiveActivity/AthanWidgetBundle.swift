import WidgetKit
import SwiftUI
import AlarmKit

/// Widget bundle that registers the prayer alarm's Live Activity with the system.
/// AlarmKit requires a `Widget` conforming to `AlarmWidget` for the alarm's
/// Lock Screen / Dynamic Island / StandBy presentation.
@main
struct AthanWidgetBundle: WidgetBundle {
    var body: some Widget {
        PrayerAlarmWidget()
    }
}

/// The alarm widget that provides the Live Activity interface for prayer alarms.
///
/// Defines the Lock Screen banner, Dynamic Island expanded/compact/minimal views,
/// and StandBy presentation when a prayer alarm fires or is in snooze countdown.
struct PrayerAlarmWidget: AlarmWidget {
    var body: some AlarmWidgetConfiguration {
        AlarmWidgetConfiguration(for: PrayerAlarmMetadata.self) { context in
            // Lock Screen / StandBy expanded view
            PrayerAlarmLockScreenView(context: context)
        } dynamicIsland: { context in
            AlarmDynamicIsland(context: context) {
                // Expanded: leading
                DynamicIslandExpandedRegion(.leading) {
                    Label(displayName(for: context), systemImage: "moon.stars.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                // Expanded: trailing
                DynamicIslandExpandedRegion(.trailing) {
                    AlarmTimerView(context: context)
                        .font(.title2.monospacedDigit())
                }
                // Expanded: bottom
                DynamicIslandExpandedRegion(.bottom) {
                    AlarmButtonsView(context: context)
                }
            } compactLeading: {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(Color(hex: AppConstants.Defaults.tintColorHex))
            } compactTrailing: {
                AlarmTimerView(context: context)
                    .font(.caption.monospacedDigit())
            } minimal: {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(Color(hex: AppConstants.Defaults.tintColorHex))
            }
        }
    }

    private func displayName(for context: AlarmWidgetContext<PrayerAlarmMetadata>) -> String {
        Prayer(rawValue: context.metadata.prayerName)?.displayName
            ?? context.metadata.prayerName.capitalized
    }
}

// MARK: - Lock Screen View

/// Full-width Lock Screen banner shown when a prayer alarm fires or is in snooze.
private struct PrayerAlarmLockScreenView: View {
    let context: AlarmWidgetContext<PrayerAlarmMetadata>

    private var prayerDisplayName: String {
        Prayer(rawValue: context.metadata.prayerName)?.displayName
            ?? context.metadata.prayerName.capitalized
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "moon.stars.fill")
                    .font(.title2)
                    .foregroundStyle(Color(hex: AppConstants.Defaults.tintColorHex))

                Text(prayerDisplayName)
                    .font(.title2.bold())

                Spacer()

                AlarmTimerView(context: context)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text("It's time for \(prayerDisplayName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            AlarmButtonsView(context: context)
        }
        .padding()
    }
}
