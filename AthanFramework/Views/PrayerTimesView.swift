import SwiftUI
import SwiftData

/// Main screen showing today's 5 prayer times with alarm status.
struct PrayerTimesView: View {
    @Environment(PrayerTimesViewModel.self) private var viewModel
    @Query private var preferences: [UserPreferences]

    private var locationName: String {
        preferences.first?.locationName ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Gradient header with location, hijri date, and countdown
                    headerSection

                    // Prayer cards
                    prayerCardsSection

                    // Error display with retry
                    if let error = viewModel.errorMessage {
                        errorSection(error)
                    }

                    // Loading state
                    if viewModel.isLoading && viewModel.todayTimes == nil {
                        loadingSection
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Prayer Times")
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                viewModel.loadTodayTimes()
                if viewModel.todayTimes == nil {
                    await viewModel.refresh()
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Location and date
            VStack(spacing: 4) {
                if !locationName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption)
                        Text(locationName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Location: \(locationName)")
                }

                if !viewModel.hijriDate.isEmpty {
                    Text(viewModel.hijriDate)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .accessibilityLabel("Islamic date: \(viewModel.hijriDate)")
                }
            }

            // Countdown to next prayer
            if let next = viewModel.nextPrayer,
               let countdown = viewModel.countdownToNext {
                VStack(spacing: 4) {
                    Text(next.displayName.uppercased())
                        .font(.caption)
                        .fontWeight(.bold)
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.7))

                    Text(countdown)
                        .font(.title)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Next prayer is \(next.displayName) in \(countdown)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: nextPrayerColorHex).opacity(0.85),
                    Color(hex: nextPrayerColorHex)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color(hex: nextPrayerColorHex).opacity(0.3), radius: 8, y: 4)
    }

    private var nextPrayerColorHex: String {
        viewModel.nextPrayer?.colorHex ?? AppConstants.Defaults.tintColorHex
    }

    // MARK: - Prayer Cards

    private var prayerCardsSection: some View {
        VStack(spacing: 8) {
            ForEach(Prayer.allCases) { prayer in
                PrayerRow(
                    prayer: prayer,
                    timeString: viewModel.timeString(for: prayer),
                    isEnabled: viewModel.alarmConfigs.first(where: {
                        $0.prayerName == prayer.rawValue
                    })?.isEnabled ?? true,
                    hasPassed: viewModel.hasPassed(prayer),
                    isNext: viewModel.nextPrayer == prayer,
                    offsetDescription: viewModel.offsetDescription(for: prayer),
                    onToggle: { viewModel.toggleAlarm(for: prayer) }
                )

                // Sunrise row between Fajr and Dhuhr
                if prayer == .fajr {
                    SunriseRow(
                        timeString: viewModel.sunriseTimeString,
                        hasPassed: viewModel.sunriseHasPassed
                    )
                }
            }
        }
    }

    // MARK: - Error & Loading

    private func errorSection(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.callout)

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.callout)
                    .fontWeight(.medium)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(error). Double tap to retry.")
    }

    private var loadingSection: some View {
        HStack {
            Spacer()
            ProgressView("Loading prayer times...")
                .font(.subheadline)
            Spacer()
        }
        .padding()
    }
}

/// A single prayer time row styled as a card.
struct PrayerRow: View {
    let prayer: Prayer
    let timeString: String
    let isEnabled: Bool
    let hasPassed: Bool
    let isNext: Bool
    var offsetDescription: String? = nil
    let onToggle: () -> Void

    @State private var bellAnimating = false

    private var prayerColor: Color {
        Color(hex: prayer.colorHex)
    }

    var body: some View {
        NavigationLink {
            PrayerDetailView(prayer: prayer)
        } label: {
            HStack(spacing: 12) {
                // Prayer icon with color
                Image(systemName: prayer.sfSymbol)
                    .font(isNext ? .title2 : .title3)
                    .foregroundStyle(
                        hasPassed
                            ? Color.secondary.opacity(0.4)
                            : prayerColor
                    )
                    .frame(width: 32, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(prayer.displayName)
                            .font(isNext ? .headline : .subheadline)
                            .fontWeight(isNext ? .bold : .semibold)
                            .foregroundStyle(hasPassed ? .secondary : .primary)

                        if isNext {
                            Text("NEXT")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(prayerColor.gradient)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                                .accessibilityLabel("next prayer")
                        }
                    }

                    Text(timeString)
                        .font(isNext ? .title2 : .title3)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(hasPassed ? .secondary : .primary)
                        .contentTransition(.numericText())
                }

                Spacer()

                // Alarm toggle + offset info
                VStack(spacing: 2) {
                    Button {
                        withAnimation(.bouncy(duration: 0.3)) {
                            bellAnimating = true
                        }
                        onToggle()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            bellAnimating = false
                        }
                    } label: {
                        Image(systemName: isEnabled ? "bell.fill" : "bell.slash")
                            .font(.title3)
                            .foregroundStyle(
                                isEnabled
                                    ? prayerColor
                                    : Color.secondary.opacity(0.4)
                            )
                            .symbolEffect(.bounce, value: bellAnimating)
                            .frame(width: 44, height: 44) // Minimum 44pt touch target
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(flexibility: .soft), trigger: isEnabled)
                    .accessibilityLabel("\(prayer.displayName) alarm")
                    .accessibilityValue(isEnabled ? "On" : "Off")
                    .accessibilityHint("Double tap to \(isEnabled ? "disable" : "enable") alarm")

                    if let offset = offsetDescription, isEnabled {
                        Text(offset)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityLabel("Alarm offset: \(offset)")
                    }
                }
            }
            .padding(.vertical, isNext ? 12 : 8)
            .padding(.horizontal, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            isNext
                                ? prayerColor.opacity(0.08)
                                : Color.clear
                        )
                )
                .overlay(alignment: .leading) {
                    if !hasPassed {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 12,
                            bottomLeadingRadius: 12,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0
                        )
                        .fill(prayerColor)
                        .frame(width: 3)
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(prayerAccessibilityLabel)
    }

    private var prayerAccessibilityLabel: String {
        var label = "\(prayer.displayName), \(timeString)"
        if isNext { label += ", next prayer" }
        if hasPassed { label += ", passed" }
        label += ", alarm \(isEnabled ? "on" : "off")"
        return label
    }
}

/// Informational row showing Sunrise time. No alarm toggle, no navigation.
struct SunriseRow: View {
    let timeString: String
    let hasPassed: Bool

    private let sunriseColor = Color(hex: Prayer.sunriseColorHex)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sunrise.fill")
                .font(.title3)
                .foregroundStyle(hasPassed ? Color.secondary.opacity(0.4) : sunriseColor)
                .frame(width: 32, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Sunrise")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(hasPassed ? .secondary : .primary)

                Text(timeString)
                    .font(.title3)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(hasPassed ? .secondary : .primary)
                    .contentTransition(.numericText())
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(alignment: .leading) {
                    if !hasPassed {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 12,
                            bottomLeadingRadius: 12,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0
                        )
                        .fill(sunriseColor)
                        .frame(width: 3)
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sunrise, \(timeString)\(hasPassed ? ", passed" : "")")
    }
}
