import SwiftUI
import SwiftData

/// Settings screen: calculation method, location, calendar, school selection.
struct SettingsView: View {
    @Environment(SettingsViewModel.self) private var viewModel

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
                    .tint(Color(hex: AppConstants.Defaults.tintColorHex))
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
                    .tint(Color(hex: AppConstants.Defaults.tintColorHex))
                    .accessibilityLabel("Calendar sync")
                    .accessibilityValue(viewModel.preferences?.calendarSyncEnabled == true ? "On" : "Off")

                    if viewModel.preferences?.calendarSyncEnabled == true {
                        Toggle(isOn: Binding(
                            get: { viewModel.preferences?.calendarSyncAhead ?? false },
                            set: { viewModel.toggleCalendarSyncAhead($0) }
                        )) {
                            Label("30 Days Ahead", systemImage: "calendar.badge.plus")
                        }
                        .tint(Color(hex: AppConstants.Defaults.tintColorHex))
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
}
