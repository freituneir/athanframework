import SwiftUI
import SwiftData

/// Detail view for a single prayer: toggle alarm, pick sound, set snooze interval, offset.
struct PrayerDetailView: View {
    let prayer: Prayer

    @Query private var configs: [PrayerAlarmConfig]
    @Environment(\.modelContext) private var context

    private var config: PrayerAlarmConfig? {
        configs.first(where: { $0.prayerName == prayer.rawValue })
    }

    var body: some View {
        Form {
            // Prayer info header
            Section {
                HStack(spacing: 16) {
                    Image(systemName: prayer.sfSymbol)
                        .font(.system(size: 36))
                        .foregroundStyle(AthanTheme.accent.gradient)
                        .frame(width: 48, height: 48)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(prayer.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(prayer.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(prayer.displayName), \(prayer.subtitle)")
            }

            // Alarm section
            Section {
                if let config = config {
                    Toggle(isOn: Binding(
                        get: { config.isEnabled },
                        set: { config.isEnabled = $0; try? context.save() }
                    )) {
                        Label("Alarm", systemImage: config.isEnabled ? "bell.fill" : "bell.slash")
                            .foregroundStyle(config.isEnabled ? .primary : .secondary)
                    }
                    .tint(AthanTheme.accent)
                    .sensoryFeedback(.impact(flexibility: .soft), trigger: config.isEnabled)
                    .accessibilityLabel("Alarm")
                    .accessibilityValue(config.isEnabled ? "Enabled" : "Disabled")

                    NavigationLink {
                        SoundPickerView(selectedSound: Binding(
                            get: { config.soundFileName },
                            set: { config.soundFileName = $0; try? context.save() }
                        ))
                    } label: {
                        HStack {
                            Label("Sound", systemImage: "speaker.wave.2.fill")
                            Spacer()
                            Text(SoundManager.displayName(for: config.soundFileName))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("Alarm sound")
                    .accessibilityValue(SoundManager.displayName(for: config.soundFileName))
                } else {
                    ContentUnavailableView(
                        "Configuration Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Unable to load alarm settings. Pull to refresh on the main screen.")
                    )
                }
            } header: {
                Text("Alarm")
            }

            // Snooze section
            Section {
                if let config = config {
                    Picker(selection: Binding(
                        get: { config.snoozeDurationSeconds },
                        set: { config.snoozeDurationSeconds = $0; try? context.save() }
                    )) {
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                        Text("3 minutes").tag(180)
                        Text("5 minutes").tag(300)
                        Text("10 minutes").tag(600)
                        Text("15 minutes").tag(900)
                        Text("30 minutes").tag(1800)
                    } label: {
                        Label("Interval", systemImage: "arrow.clockwise")
                    }
                    .accessibilityLabel("Snooze interval")
                    .accessibilityValue(snoozeValueDescription(config.snoozeDurationSeconds))
                }
            } header: {
                Text("Snooze")
            } footer: {
                if let config = config {
                    Text("The alarm will repeat every \(config.snoozeDurationSeconds / 60) minute\(config.snoozeDurationSeconds / 60 == 1 ? "" : "s") until you tap Done.")
                }
            }

            // Offset section
            Section {
                if let config = config {
                    // Fajr-only: toggle to offset relative to Sunrise instead of Fajr time
                    if prayer == .fajr {
                        Toggle(isOn: Binding(
                            get: { config.usesSunriseOffset },
                            set: { config.usesSunriseOffset = $0; try? context.save() }
                        )) {
                            Label("Relative to Sunrise", systemImage: "sunrise.fill")
                        }
                        .tint(.orange)
                    }

                    Stepper(
                        value: Binding(
                            get: { config.offsetMinutes },
                            set: { config.offsetMinutes = $0; try? context.save() }
                        ),
                        in: -60...60,
                        step: 5
                    ) {
                        Label {
                            if config.offsetMinutes == 0 {
                                Text(config.usesSunriseOffset && prayer == .fajr ? "At sunrise" : "At prayer time")
                            } else if config.offsetMinutes < 0 {
                                Text("\(abs(config.offsetMinutes)) min before\(config.usesSunriseOffset && prayer == .fajr ? " sunrise" : "")")
                            } else {
                                Text("\(config.offsetMinutes) min after\(config.usesSunriseOffset && prayer == .fajr ? " sunrise" : "")")
                            }
                        } icon: {
                            Image(systemName: "clock.arrow.2.circlepath")
                        }
                    }
                    .sensoryFeedback(.selection, trigger: config.offsetMinutes)
                    .accessibilityLabel("Alarm offset")
                    .accessibilityValue(offsetAccessibilityValue(config.offsetMinutes))
                    .accessibilityHint("Adjustable. Swipe up or down to change by 5 minute increments.")
                }
            } header: {
                Text("Offset")
            } footer: {
                if let config = config, config.usesSunriseOffset, prayer == .fajr {
                    Text("Adjust when the alarm fires relative to sunrise.")
                } else {
                    Text("Adjust when the alarm fires relative to the actual prayer time.")
                }
            }
        }
        .navigationTitle(prayer.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Accessibility Helpers

    private func snoozeValueDescription(_ seconds: Int) -> String {
        let minutes = seconds / 60
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    private func offsetAccessibilityValue(_ minutes: Int) -> String {
        if minutes == 0 {
            return "At prayer time"
        } else if minutes < 0 {
            return "\(abs(minutes)) minutes before prayer time"
        } else {
            return "\(minutes) minutes after prayer time"
        }
    }
}
