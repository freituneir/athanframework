import SwiftUI
import SwiftData

/// Settings screen: calculation method, location, calendar, school selection.
struct SettingsView: View {
    @Environment(SettingsViewModel.self) private var viewModel
    @Environment(AlarmSchedulingService.self) private var alarmService
    @State private var testAlarmIndex = 0
    @State private var testAlarmError: String?
    @State private var testFireTime: (label: String, date: Date)?
    @State private var stoppedCount: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: Binding(
                        get: { viewModel.preferences?.calculationMethod ?? .isna },
                        set: { viewModel.updateCalculationMethod($0) }
                    )) {
                        ForEach(CalculationMethod.allCases) { method in
                            Text(method.displayName).tag(method)
                        }
                    } label: {
                        Label("Method", systemImage: "function")
                    }
                    .accessibilityLabel("Calculation method")

                    Picker(selection: Binding(
                        get: { viewModel.preferences?.school ?? .shafi },
                        set: { viewModel.updateSchool($0) }
                    )) {
                        ForEach(AsrSchool.allCases) { school in
                            Text(school.displayName).tag(school)
                        }
                    } label: {
                        Label("Asr School", systemImage: "book.closed.fill")
                    }
                    .accessibilityLabel("Asr juristic school")
                } header: {
                    Text("Prayer Calculation")
                } footer: {
                    Text("The calculation method determines Fajr and Isha angles. Choose the method recommended for your region.")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { viewModel.preferences?.useAutoLocation ?? true },
                        set: { viewModel.toggleAutoLocation($0) }
                    )) {
                        Label("Auto-detect", systemImage: "location.fill")
                    }
                    .tint(AthanTheme.accent)
                    .accessibilityLabel("Auto-detect location")
                    .accessibilityValue(viewModel.preferences?.useAutoLocation == true ? "On" : "Off")

                    if let prefs = viewModel.preferences {
                        if !prefs.locationName.isEmpty {
                            HStack {
                                Label("Current", systemImage: "mappin.circle.fill")
                                Spacer()
                                Text(prefs.locationName)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Current location: \(prefs.locationName)")
                        }

                        if !prefs.useAutoLocation {
                            HStack {
                                Label("Coordinates", systemImage: "globe")
                                Spacer()
                                Text(String(format: "%.4f, %.4f", prefs.latitude, prefs.longitude))
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Coordinates: latitude \(String(format: "%.4f", prefs.latitude)), longitude \(String(format: "%.4f", prefs.longitude))")
                        }
                    }
                } header: {
                    Text("Location")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { viewModel.preferences?.calendarSyncEnabled ?? false },
                        set: { viewModel.toggleCalendarSync($0) }
                    )) {
                        Label("Sync to Calendar", systemImage: "calendar.badge.clock")
                    }
                    .tint(AthanTheme.accent)
                    .accessibilityLabel("Calendar sync")
                    .accessibilityValue(viewModel.preferences?.calendarSyncEnabled == true ? "On" : "Off")

                    if viewModel.preferences?.calendarSyncEnabled == true {
                        Toggle(isOn: Binding(
                            get: { viewModel.preferences?.calendarSyncAhead ?? false },
                            set: { viewModel.toggleCalendarSyncAhead($0) }
                        )) {
                            Label("30 Days Ahead", systemImage: "calendar.badge.plus")
                        }
                        .tint(AthanTheme.accent)
                        .accessibilityLabel("Sync 30 days ahead")
                        .accessibilityValue(viewModel.preferences?.calendarSyncAhead == true ? "On" : "Off")
                    }
                } header: {
                    Text("Calendar")
                } footer: {
                    if viewModel.preferences?.calendarSyncEnabled == true {
                        Text(viewModel.preferences?.calendarSyncAhead == true
                            ? "Prayer times for the next 30 days will appear as events in your calendar."
                            : "Today's prayer times will appear as events in your calendar.")
                    }
                }

                Section {
                    Picker(selection: Binding(
                        get: { viewModel.preferences?.selectedTheme ?? .green },
                        set: { viewModel.updateTheme($0) }
                    )) {
                        ForEach(ColorTheme.allCases) { theme in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(theme.swatchColor)
                                    .frame(width: 14, height: 14)
                                Text(theme.displayName)
                            }
                            .tag(theme)
                        }
                    } label: {
                        Label("Color Theme", systemImage: "paintpalette.fill")
                    }
                } header: {
                    Text("Appearance")
                }

                Section {
                    NavigationLink {
                        AthanSoundPickerView(
                            selected: viewModel.preferences?.selectedAthanSound ?? .defaultTone,
                            onSelect: { viewModel.updateAthanSound($0) }
                        )
                    } label: {
                        HStack {
                            Label("Athan Reciter", systemImage: "music.note")
                            Spacer()
                            Text(viewModel.preferences?.selectedAthanSound.displayName ?? "Default")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Athan Sound")
                } footer: {
                    Text("Choose the athan recitation played when a prayer alarm fires.")
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hardware buttons dismiss the alarm sound.")
                            Text("If the prayer isn\u{2019}t marked done, the reminder will appear on your lock screen.")
                        }
                        .font(.subheadline)
                        .foregroundStyle(AthanTheme.textSecondary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(AthanTheme.accent.opacity(0.6))
                    }
                } header: {
                    Text("Alarm Tips")
                }

                Section {
                    NavigationLink {
                        ScheduledAlarmsView()
                    } label: {
                        Label("Scheduled Alarms", systemImage: "alarm.fill")
                    }
                } header: {
                    Text("Alarms")
                }

                Section {
                    Button {
                        scheduleTestAlarm(label: "Test") {
                            let sound = viewModel.preferences?.selectedAthanSound ?? .defaultTone
                            return try await alarmService.scheduleTestAlarmCorrected(index: testAlarmIndex, athanSound: sound)
                        }
                    } label: {
                        Label("Test Alarm + Pray Now (90s)", systemImage: "bell.badge")
                    }

                    Button(role: .destructive) {
                        DebugLog.shared.log("Stop All: tapped")
                        stoppedCount = alarmService.stopAllAlarms()
                        testFireTime = nil
                    } label: {
                        Label("Stop All Alarms", systemImage: "xmark.octagon.fill")
                    }

                    if let fireInfo = testFireTime {
                        Text("\(fireInfo.label): \(fireInfo.date.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let error = testAlarmError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let count = stoppedCount {
                        Text("Stopped \(count) alarm(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Auth: \(alarmService.isAuthorized ? "Authorized" : "Not authorized")")
                        .font(.caption)
                        .foregroundStyle(alarmService.isAuthorized ? .green : .red)

                    NavigationLink {
                        DebugLogView()
                    } label: {
                        Label("Debug Log (\(DebugLog.shared.entries.count))", systemImage: "doc.text.magnifyingglass")
                    }
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Alarm + Pray Now: countdown at +30s, alarm fires at +90s, snooze=30s. 'Pray Now' LA appears immediately and persists through dismiss/snooze/hardware-dismiss. Tap Done on the Pray Now LA to dismiss it.")
                }

                Section {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("App version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                viewModel.loadPreferences()
            }
        }
    }

    private func scheduleTestAlarm(label: String, action: @escaping () async throws -> Date) {
        testAlarmError = nil
        stoppedCount = nil
        testAlarmIndex += 1
        Task {
            do {
                let fireDate = try await action()
                testFireTime = (label, fireDate)
            } catch {
                DebugLog.shared.error("\(label) FAILED: \(error)")
                testAlarmError = "\(label): \(error.localizedDescription)"
            }
        }
    }
}
