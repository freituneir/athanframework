import SwiftUI

/// Main screen showing today's 5 prayer times with alarm status.
struct PrayerTimesView: View {
    @Environment(PrayerTimesViewModel.self) private var viewModel

    var body: some View {
        NavigationStack {
            List {
                // Hijri date header
                if !viewModel.hijriDate.isEmpty {
                    Section {
                        Text(viewModel.hijriDate)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                            .accessibilityLabel("Islamic date: \(viewModel.hijriDate)")
                    }
                }

                // Countdown to next prayer
                if let next = viewModel.nextPrayer,
                   let countdown = viewModel.countdownToNext {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.fill")
                                .font(.title3)
                                .foregroundStyle(Color(hex: AppConstants.Defaults.tintColorHex))
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Next: \(next.displayName)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(countdown)
                                    .font(.title3)
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
                            onToggle: { viewModel.toggleAlarm(for: prayer) }
                        )
                    }
                }

                // Error display with retry
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
            }
        }
    }
}

/// A single prayer time row.
struct PrayerRow: View {
    let prayer: Prayer
    let timeString: String
    let isEnabled: Bool
    let hasPassed: Bool
    let isNext: Bool
    let onToggle: () -> Void

    @State private var bellAnimating = false

    var body: some View {
        NavigationLink {
            PrayerDetailView(prayer: prayer)
        } label: {
            HStack(spacing: 12) {
                // Prayer icon
                Image(systemName: prayer.sfSymbol)
                    .font(.title3)
                    .foregroundStyle(isNext ? Color(hex: AppConstants.Defaults.tintColorHex) : (hasPassed ? .tertiary : .secondary))
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

                // Alarm toggle button - separate from NavigationLink tap area
                Button {
                    withAnimation(.bouncy(duration: 0.3)) {
                        bellAnimating = true
                    }
                    onToggle()
                    // Reset animation state
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        bellAnimating = false
                    }
                } label: {
                    Image(systemName: isEnabled ? "bell.fill" : "bell.slash")
                        .font(.title3)
                        .foregroundStyle(isEnabled ? Color(hex: AppConstants.Defaults.tintColorHex) : .tertiary)
                        .symbolEffect(.bounce, value: bellAnimating)
                        .frame(width: 44, height: 44) // Minimum 44pt touch target
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(flexibility: .soft), trigger: isEnabled)
                .accessibilityLabel("\(prayer.displayName) alarm")
                .accessibilityValue(isEnabled ? "On" : "Off")
                .accessibilityHint("Double tap to \(isEnabled ? "disable" : "enable") alarm")
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
