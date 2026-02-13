import SwiftUI

/// List of custom reminders with add/edit/delete capability.
struct CustomRemindersView: View {
    @Environment(CustomReminderViewModel.self) private var viewModel
    @State private var showingAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.reminders.isEmpty {
                    ContentUnavailableView {
                        Label("No Reminders", systemImage: "bell.slash")
                    } description: {
                        Text("Add custom reminders for Quran reading, dhikr, or anything else.")
                    } actions: {
                        Button {
                            showingAddSheet = true
                        } label: {
                            Label("Add Reminder", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: AppConstants.Defaults.tintColorHex))
                    }
                } else {
                    List {
                        ForEach(viewModel.reminders, id: \.id) { reminder in
                            ReminderRow(
                                reminder: reminder,
                                onToggle: { viewModel.toggleReminder(reminder) }
                            )
                        }
                        .onDelete { indexSet in
                            Task {
                                for index in indexSet {
                                    try? await viewModel.deleteReminder(viewModel.reminders[index])
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reminders")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add new reminder")
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddReminderView()
            }
            .onAppear {
                viewModel.loadReminders()
            }
        }
    }
}

// MARK: - Reminder Row

struct ReminderRow: View {
    let reminder: CustomReminder
    let onToggle: () -> Void

    @State private var bellAnimating = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.headline)
                    .foregroundStyle(reminder.isEnabled ? .primary : .secondary)

                if let time = reminder.scheduledTime {
                    Text(DateFormatter.prayerTime.string(from: time))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if reminder.isRecurring && !reminder.recurrenceDays.isEmpty {
                    Text(recurrenceDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                withAnimation(.bouncy(duration: 0.3)) {
                    bellAnimating = true
                }
                onToggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    bellAnimating = false
                }
            } label: {
                Image(systemName: reminder.isEnabled ? "bell.fill" : "bell.slash")
                    .foregroundStyle(reminder.isEnabled ? Color(hex: AppConstants.Defaults.tintColorHex) : .tertiary)
                    .symbolEffect(.bounce, value: bellAnimating)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: reminder.isEnabled)
            .accessibilityLabel("\(reminder.title) alarm")
            .accessibilityValue(reminder.isEnabled ? "On" : "Off")
            .accessibilityHint("Double tap to \(reminder.isEnabled ? "disable" : "enable")")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(reminderAccessibilityLabel)
    }

    private var recurrenceDescription: String {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let days = reminder.recurrenceDays.compactMap { day -> String? in
            guard day >= 1, day <= 7 else { return nil }
            return dayNames[day - 1]
        }
        return days.joined(separator: ", ")
    }

    private var reminderAccessibilityLabel: String {
        var label = reminder.title
        if let time = reminder.scheduledTime {
            label += ", \(DateFormatter.prayerTime.string(from: time))"
        }
        if reminder.isRecurring {
            label += ", repeats \(recurrenceDescription)"
        }
        label += ", alarm \(reminder.isEnabled ? "on" : "off")"
        return label
    }
}

// MARK: - Add Reminder Sheet

/// Sheet for adding a new custom reminder.
struct AddReminderView: View {
    @Environment(CustomReminderViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var notes = ""
    @State private var scheduledTime = Date()
    @State private var isRecurring = false
    @State private var selectedDays: Set<Int> = []
    @State private var snoozeDuration = AppConstants.Defaults.snoozeDurationOther

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .accessibilityLabel("Reminder title")
                    TextField("Notes (optional)", text: $notes)
                        .accessibilityLabel("Reminder notes")
                } header: {
                    Text("Details")
                }

                Section {
                    DatePicker("When", selection: $scheduledTime, displayedComponents: [.date, .hourAndMinute])
                        .accessibilityLabel("Reminder time")
                } header: {
                    Text("Time")
                }

                Section {
                    Toggle(isOn: $isRecurring) {
                        Label("Recurring", systemImage: "repeat")
                    }
                    .tint(Color(hex: AppConstants.Defaults.tintColorHex))
                    .accessibilityLabel("Recurring reminder")

                    if isRecurring {
                        DayPicker(selectedDays: $selectedDays)
                            .padding(.vertical, 4)
                    }
                } header: {
                    Text("Repeat")
                }

                Section {
                    Picker(selection: $snoozeDuration) {
                        Text("2 minutes").tag(120)
                        Text("5 minutes").tag(300)
                        Text("10 minutes").tag(600)
                        Text("15 minutes").tag(900)
                    } label: {
                        Label("Snooze Interval", systemImage: "arrow.clockwise")
                    }
                    .accessibilityLabel("Snooze interval")
                } header: {
                    Text("Alarm")
                }
            }
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            try? await viewModel.addReminder(
                                title: title,
                                notes: notes,
                                scheduledTime: scheduledTime,
                                isRecurring: isRecurring,
                                recurrenceDays: Array(selectedDays),
                                snoozeDuration: snoozeDuration
                            )
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .sensoryFeedback(.success, trigger: title)
                }
            }
        }
    }
}

// MARK: - Day Picker

/// Day-of-week picker for recurring reminders.
struct DayPicker: View {
    @Binding var selectedDays: Set<Int>

    private let days: [(Int, String, String)] = [
        (1, "S", "Sunday"),
        (2, "M", "Monday"),
        (3, "T", "Tuesday"),
        (4, "W", "Wednesday"),
        (5, "T", "Thursday"),
        (6, "F", "Friday"),
        (7, "S", "Saturday")
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(days, id: \.0) { day, label, fullName in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if selectedDays.contains(day) {
                            selectedDays.remove(day)
                        } else {
                            selectedDays.insert(day)
                        }
                    }
                } label: {
                    Text(label)
                        .font(.caption)
                        .fontWeight(.bold)
                        .frame(width: 36, height: 36)
                        .background(
                            selectedDays.contains(day)
                                ? Color(hex: AppConstants.Defaults.tintColorHex)
                                : Color(.systemGray5)
                        )
                        .foregroundStyle(selectedDays.contains(day) ? .white : .primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: selectedDays.contains(day))
                .accessibilityLabel(fullName)
                .accessibilityValue(selectedDays.contains(day) ? "Selected" : "Not selected")
                .accessibilityHint("Double tap to \(selectedDays.contains(day) ? "deselect" : "select")")
                .accessibilityAddTraits(selectedDays.contains(day) ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
