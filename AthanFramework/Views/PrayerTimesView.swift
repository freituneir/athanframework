import SwiftUI
import SwiftData

/// Main screen showing today's 5 prayer times with alarm status.
struct PrayerTimesView: View {
    @Environment(PrayerTimesViewModel.self) private var viewModel
    @Environment(\.scenePhase) private var scenePhase
    @Query private var preferences: [UserPreferences]

    private var locationName: String {
        preferences.first?.locationName ?? ""
    }

    var body: some View {
        NavigationStack {
            List {
                // Location + Hijri date header
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        if !locationName.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "location.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color(hex: AppConstants.Defaults.tintColorHex))
                                Text(locationName)
                                    .font(.headline)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Location: \(locationName)")
                        }

                        if !viewModel.hijriDate.isEmpty {
                            Text(viewModel.hijriDate)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Islamic date: \(viewModel.hijriDate)")
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                // Countdown to next prayer
                if let next = viewModel.nextPrayer,
                   let countdown = viewModel.countdownToNext {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: next.sfSymbol)
                                .font(.title2)
                                .foregroundStyle(Color(hex: next.colorHex))
                                .frame(width: 32)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Next: \(next.displayName)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(countdown)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                            }

                            Spacer()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Next prayer is \(next.displayName) in \(countdown)")
                    }
                }

                // Prayer rows
                Section {
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
                            isCompleted: viewModel.isCompleted(prayer),
                            onToggleCompletion: { viewModel.toggleCompletion(for: prayer) },
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

                // Error display
                if let error = viewModel.errorMessage {
                    Section {
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
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Error: \(error). Double tap to retry.")
                    }
                }

                // Loading state
                if viewModel.isLoading && viewModel.todayTimes == nil {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Loading prayer times...")
                                .font(.subheadline)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Prayer Times")
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                viewModel.loadTodayTimes()
                if viewModel.todayTimes == nil {
                    await viewModel.refresh()
                }
                // Periodic check every 10 min: ensure all future prayer alarms are scheduled.
                // Covers midnight rollover and any alarms that may have been cleared.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(600))
                    await viewModel.refreshIfNeeded()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.loadTodayTimes()
                    Task { await viewModel.refreshIfNeeded() }
                }
            }
        }
    }
}

/// A single prayer time row — clean, native iOS style.
struct PrayerRow: View {
    let prayer: Prayer
    let timeString: String
    let isEnabled: Bool
    let hasPassed: Bool
    let isNext: Bool
    var offsetDescription: String? = nil
    var isCompleted: Bool = false
    var onToggleCompletion: (() -> Void)? = nil
    let onToggle: () -> Void

    @State private var bellAnimating = false

    var body: some View {
        NavigationLink {
            PrayerDetailView(prayer: prayer)
        } label: {
            HStack(spacing: 12) {
                // Completion circle
                if let onToggleCompletion {
                    Button {
                        onToggleCompletion()
                    } label: {
                        Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(
                                isCompleted
                                    ? Color(hex: AppConstants.Defaults.tintColorHex)
                                    : Color.secondary.opacity(0.4)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.success, trigger: isCompleted)
                    .accessibilityLabel("Mark \(prayer.displayName) as \(isCompleted ? "incomplete" : "complete")")
                }

                // Prayer icon with per-prayer color
                Image(systemName: prayer.sfSymbol)
                    .font(.title3)
                    .foregroundStyle(
                        hasPassed
                            ? Color.secondary.opacity(0.5)
                            : Color(hex: prayer.colorHex)
                    )
                    .frame(width: 28, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(prayer.displayName)
                            .font(.headline)
                            .foregroundStyle(hasPassed ? .secondary : .primary)

                        if isNext {
                            Text("NEXT")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: AppConstants.Defaults.tintColorHex).gradient)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                                .accessibilityLabel("next prayer")
                        }
                    }

                    Text(timeString)
                        .font(.title2)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(hasPassed ? .secondary : .primary)
                        .contentTransition(.numericText())
                }

                Spacer()

                // Alarm toggle + offset
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
                                    ? Color(hex: AppConstants.Defaults.tintColorHex)
                                    : Color.secondary.opacity(0.5)
                            )
                            .symbolEffect(.bounce, value: bellAnimating)
                            .frame(width: 44, height: 44)
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
            .padding(.vertical, 4)
        }
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

    var body: some View {
        HStack(spacing: 12) {
            // Invisible spacer to align with prayer rows' completion circles
            Color.clear
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            Image(systemName: "sunrise.fill")
                .font(.title3)
                .foregroundStyle(hasPassed ? Color.secondary.opacity(0.5) : .orange)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Sunrise")
                    .font(.headline)
                    .foregroundStyle(hasPassed ? .secondary : .primary)

                Text(timeString)
                    .font(.title2)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(hasPassed ? .secondary : .primary)
                    .contentTransition(.numericText())
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sunrise, \(timeString)\(hasPassed ? ", passed" : "")")
    }
}
