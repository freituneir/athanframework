import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct PrayerTimesEntry: TimelineEntry {
    let date: Date
    let prayers: [(prayer: Prayer, time: Date)]
    let sunrise: Date?
    let completedPrayers: Set<String>
}

// MARK: - Timeline Provider

struct PrayerTimesProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrayerTimesEntry {
        PrayerTimesEntry(
            date: .now,
            prayers: Prayer.allCases.map { ($0, .now) },
            sunrise: .now,
            completedPrayers: []
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PrayerTimesEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerTimesEntry>) -> Void) {
        let entry = readEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: .now)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func readEntry() -> PrayerTimesEntry {
        let suite = UserDefaults(suiteName: AppConstants.AppGroup.suiteName)

        let timesDict = suite?.dictionary(forKey: AppConstants.AppGroup.prayerTimesKey) as? [String: Double] ?? [:]
        var prayers: [(Prayer, Date)] = []
        for prayer in Prayer.allCases {
            if let ts = timesDict[prayer.rawValue] {
                prayers.append((prayer, Date(timeIntervalSince1970: ts)))
            }
        }
        let sunrise: Date? = timesDict["sunrise"].map { Date(timeIntervalSince1970: $0) }

        let completed = suite?.dictionary(forKey: AppConstants.AppGroup.completedKey) as? [String: Double] ?? [:]
        let completedSet = Set(completed.keys)

        return PrayerTimesEntry(
            date: .now,
            prayers: prayers,
            sunrise: sunrise,
            completedPrayers: completedSet
        )
    }
}

// MARK: - Widget Views

struct PrayerTimesWidgetEntryView: View {
    var entry: PrayerTimesEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        default:
            mediumView
        }
    }

    // MARK: - Small Widget

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            athanHeader

            Spacer()

            if let next = nextPrayer {
                Text(next.prayer.displayName)
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundStyle(AthanTheme.textPrimary)

                Text(DateFormatter.prayerTime.string(from: next.time))
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(AthanTheme.textSecondary)
                    .monospacedDigit()

                Text(next.time, style: .relative)
                    .font(.system(size: 12))
                    .foregroundStyle(AthanTheme.accent.opacity(0.6))
                    .lineLimit(1)
            } else {
                Text("All Done")
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(AthanTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .containerBackground(for: .widget) {
            AthanTheme.backgroundGradient
        }
    }

    // MARK: - Medium Widget

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                athanHeader
                Spacer()
                Text(Date.now.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(AthanTheme.textSecondary.opacity(0.75))
            }
            .padding(.bottom, 10)

            HStack(spacing: 0) {
                ForEach(entry.prayers, id: \.prayer) { item in
                    let isNext = item.prayer == nextPrayer?.prayer
                    let passed = item.time < Date.now
                    let completed = entry.completedPrayers.contains(item.prayer.rawValue)

                    VStack(spacing: 4) {
                        Image(systemName: item.prayer.sfSymbol)
                            .font(.system(size: 14))
                            .foregroundStyle(
                                isNext ? AthanTheme.accent :
                                completed ? AthanTheme.accent.opacity(0.4) :
                                passed ? AthanTheme.textSecondary.opacity(0.35) :
                                AthanTheme.textSecondary.opacity(0.85)
                            )

                        Text(item.prayer.displayName)
                            .font(.system(size: 11, weight: isNext ? .semibold : .regular))
                            .foregroundStyle(
                                isNext ? AthanTheme.textPrimary :
                                passed ? AthanTheme.textSecondary.opacity(0.5) :
                                AthanTheme.textSecondary
                            )

                        Text(DateFormatter.prayerTime.string(from: item.time))
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(
                                isNext ? AthanTheme.accent :
                                passed ? AthanTheme.textSecondary.opacity(0.35) :
                                AthanTheme.textSecondary.opacity(0.85)
                            )
                            .monospacedDigit()

                        if completed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(AthanTheme.accent.opacity(0.5))
                        } else {
                            Color.clear.frame(height: 10)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .containerBackground(for: .widget) {
            AthanTheme.backgroundGradient
        }
    }

    // MARK: - Large Widget (mirrors NextPrayerCard from main app)

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top section: Next Prayer card
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NEXT PRAYER")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AthanTheme.accent.opacity(0.5))
                            .tracking(2.5)

                        if let next = nextPrayer {
                            Text(next.prayer.displayName)
                                .font(.system(size: 36, weight: .regular, design: .serif))
                                .foregroundStyle(AthanTheme.textPrimary)
                        } else {
                            Text("All Done")
                                .font(.system(size: 36, weight: .regular, design: .serif))
                                .foregroundStyle(AthanTheme.textSecondary)
                        }
                    }
                    Spacer()
                    // Sun icon
                    WidgetSunIcon()
                        .frame(width: 52, height: 52)
                }
                .padding(.bottom, 20)

                // Countdown
                if let next = nextPrayer {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(next.time, style: .timer)
                            .font(.system(size: 56, weight: .light, design: .serif))
                            .foregroundStyle(AthanTheme.textPrimary)
                            .monospacedDigit()

                        Text("REMAINING")
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(AthanTheme.textSecondary)
                            .tracking(1)
                            .padding(.leading, 4)
                    }
                    .padding(.bottom, 16)

                    // Progress bar
                    WidgetProgressBar(progress: progressBetweenPrayers)
                        .padding(.bottom, 16)

                    // Adhan time
                    (Text("Adhan at ")
                        .foregroundStyle(AthanTheme.textSecondary)
                     + Text(DateFormatter.prayerTime.string(from: next.time))
                        .foregroundStyle(AthanTheme.textPrimary.opacity(0.7)))
                    .font(.system(size: 15))
                }
            }
            .padding(.bottom, 20)

            // Divider
            Rectangle()
                .fill(.white.opacity(0.06))
                .frame(height: 1)
                .padding(.bottom, 16)

            // Bottom section: All 5 prayers
            HStack(spacing: 0) {
                ForEach(entry.prayers, id: \.prayer) { item in
                    let isNext = item.prayer == nextPrayer?.prayer
                    let passed = item.time < Date.now
                    let completed = entry.completedPrayers.contains(item.prayer.rawValue)

                    VStack(spacing: 3) {
                        Image(systemName: item.prayer.sfSymbol)
                            .font(.system(size: 13))
                            .foregroundStyle(
                                isNext ? AthanTheme.accent :
                                completed ? AthanTheme.accent.opacity(0.4) :
                                passed ? AthanTheme.textSecondary.opacity(0.35) :
                                AthanTheme.textSecondary.opacity(0.75)
                            )

                        Text(item.prayer.displayName)
                            .font(.system(size: 10, weight: isNext ? .semibold : .regular))
                            .foregroundStyle(
                                isNext ? AthanTheme.textPrimary :
                                passed ? AthanTheme.textSecondary.opacity(0.5) :
                                AthanTheme.textSecondary
                            )

                        Text(DateFormatter.prayerTime.string(from: item.time))
                            .font(.system(size: 11, weight: .light))
                            .foregroundStyle(
                                isNext ? AthanTheme.accent :
                                passed ? AthanTheme.textSecondary.opacity(0.35) :
                                AthanTheme.textSecondary.opacity(0.75)
                            )
                            .monospacedDigit()

                        if completed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(AthanTheme.accent.opacity(0.5))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .containerBackground(for: .widget) {
            AthanTheme.backgroundGradient
        }
    }

    // MARK: - Helpers

    private var nextPrayer: (prayer: Prayer, time: Date)? {
        entry.prayers.first { $0.time > Date.now }
    }

    /// Previous prayer (most recent that has passed).
    private var previousPrayer: (prayer: Prayer, time: Date)? {
        entry.prayers.last { $0.time <= Date.now }
    }

    /// Progress between the most recent prayer and the next (0.0–1.0).
    private var progressBetweenPrayers: Double {
        guard let next = nextPrayer else { return 1.0 }
        let prevTime: Date
        if let prev = previousPrayer {
            prevTime = prev.time
        } else {
            prevTime = Calendar.current.startOfDay(for: .now)
        }
        let total = next.time.timeIntervalSince(prevTime)
        let elapsed = Date.now.timeIntervalSince(prevTime)
        guard total > 0 else { return 0 }
        return min(max(elapsed / total, 0), 1)
    }

    // MARK: - Shared Components

    private var athanHeader: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AthanTheme.accent.opacity(0.9), AthanTheme.accentDeep.opacity(0.6)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 4
                    )
                )
                .frame(width: 8, height: 8)
            Text("ATHAN")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AthanTheme.accent.opacity(0.7))
                .tracking(1.5)
        }
    }
}

// MARK: - Widget Sub-components

private struct WidgetProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.06))

                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [AthanTheme.accent.opacity(0.6), AthanTheme.accentDeep.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * CGFloat(progress)))
            }
        }
        .frame(height: 2)
    }
}

private struct WidgetSunIcon: View {
    var body: some View {
        ZStack {
            // Outer glow halo
            Circle()
                .fill(AthanTheme.accent.opacity(0.08))
                .frame(width: 32, height: 32)
                .offset(y: -3)

            // Main orb with 3D gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AthanTheme.accent,
                            AthanTheme.accent.opacity(0.8),
                            AthanTheme.accentDeep.opacity(0.5)
                        ],
                        center: UnitPoint(x: 0.35, y: 0.35),
                        startRadius: 0,
                        endRadius: 12
                    )
                )
                .frame(width: 22, height: 22)
                .overlay {
                    // Specular highlight
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.5), .clear],
                                center: UnitPoint(x: 0.3, y: 0.3),
                                startRadius: 0,
                                endRadius: 6
                            )
                        )
                        .frame(width: 22, height: 22)
                }
                .shadow(color: AthanTheme.accent.opacity(0.5), radius: 10, y: 2)
                .offset(y: -3)

            // Horizon line
            LinearGradient(
                colors: [.clear, AthanTheme.accent.opacity(0.5), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 38, height: 1)
            .offset(y: 10)
        }
    }
}

// MARK: - Widget Configuration

struct PrayerTimesWidget: Widget {
    let kind = "PrayerTimesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrayerTimesProvider()) { entry in
            PrayerTimesWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Prayer Times")
        .description("Shows today's prayer times at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
