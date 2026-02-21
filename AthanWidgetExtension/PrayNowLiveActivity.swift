import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

/// Standalone "Pray Now" Live Activity — completely independent of AlarmKit.
/// Shows a persistent count-up timer from the prayer time with a Done button.
/// Only killed by tapping Done or marking complete in the app.
struct PrayNowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayNowAttributes.self) { context in
            prayNowLockScreen(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(AthanTheme.liveActivityBg)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        if let prayer = Prayer(rawValue: context.attributes.prayerName) {
                            Image(systemName: prayer.sfSymbol)
                                .foregroundStyle(AthanTheme.accent)
                            Text(prayer.displayName)
                        } else {
                            Text("Prayer")
                        }
                    }
                    .font(.title3)
                    .fontWeight(.semibold)
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.rawPrayerTime, style: .timer)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                        .monospacedDigit()
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Spacer()
                        Button(intent: MarkPrayerDoneIntent(prayerName: context.attributes.prayerName)) {
                            Label("Done", systemImage: "checkmark.circle.fill")
                                .lineLimit(1)
                        }
                        .tint(AthanTheme.accent)
                        .buttonStyle(.borderedProminent)
                        .frame(width: 96, height: 30)
                    }
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(AthanTheme.accent)
                        .frame(width: 10, height: 10)
                    if let prayer = Prayer(rawValue: context.attributes.prayerName) {
                        Text(prayer.displayName)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                }
            } compactTrailing: {
                if let prayer = Prayer(rawValue: context.attributes.prayerName) {
                    Image(systemName: prayer.sfSymbol)
                        .foregroundStyle(Color(hex: prayer.colorHex))
                } else {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(AthanTheme.accent)
                }
            } minimal: {
                if let prayer = Prayer(rawValue: context.attributes.prayerName) {
                    Image(systemName: prayer.sfSymbol)
                        .foregroundStyle(Color(hex: prayer.colorHex))
                } else {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(AthanTheme.accent)
                }
            }
            .keylineTint(AthanTheme.accent)
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    func prayNowLockScreen(attributes: PrayNowAttributes, state: PrayNowAttributes.ContentState) -> some View {
        let prayer = Prayer(rawValue: attributes.prayerName)

        VStack(spacing: 14) {
            // Top: prayer info + count-up timer
            HStack(alignment: .center, spacing: 10) {
                // App icon orb (same as alarm LA)
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [AthanTheme.bgLight, AthanTheme.bgDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [AthanTheme.accent, AthanTheme.accentDeep.opacity(0.4)],
                                    center: UnitPoint(x: 0.35, y: 0.35),
                                    startRadius: 0,
                                    endRadius: 7
                                )
                            )
                            .frame(width: 12, height: 12)
                            .shadow(color: AthanTheme.accent.opacity(0.5), radius: 5)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(prayer?.displayName ?? "Prayer") \u{2014} Pray Now")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AthanTheme.textPrimary)

                    Text("Since \(attributes.rawPrayerTime.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 12))
                        .foregroundStyle(AthanTheme.textSecondary)
                }

                Spacer()

                // Count-up timer from raw prayer time
                Text(attributes.rawPrayerTime, style: .timer)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.red)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            // Done button
            HStack {
                Spacer()
                Button(intent: MarkPrayerDoneIntent(prayerName: attributes.prayerName)) {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .lineLimit(1)
                }
                .tint(AthanTheme.accent)
                .buttonStyle(.borderedProminent)
                .frame(width: 96, height: 30)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}
