# Athan v2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the UI to be native iOS List-based, add AlarmKit Live Activities to widget extension, add daily prayer completion tracking with circle toggles, and create a new blue app icon.

**Architecture:** Revert PrayerTimesView to standard `List` with completion circles. Add `ActivityConfiguration` views in the widget extension for AlarmKit Live Activities on lock screen and Dynamic Island. New `PrayerCompletion` SwiftData model for daily tracking that resets each day. Programmatically generate a royal blue app icon.

**Tech Stack:** SwiftUI, SwiftData, AlarmKit, ActivityKit, WidgetKit, CoreGraphics

---

## Task 1: Revert UI — PrayerTimesView Back to Clean List

**Files:**
- Modify: `AthanFramework/Views/PrayerTimesView.swift`

**Step 1: Rewrite PrayerTimesView with List-based layout**

Replace the entire file. The new design uses standard `List` with `Section`, keeps sunrise row, keeps offset display, but removes all gradient cards, accent bars, and per-prayer colored bells.

```swift
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
    let onToggle: () -> Void

    @State private var bellAnimating = false

    var body: some View {
        NavigationLink {
            PrayerDetailView(prayer: prayer)
        } label: {
            HStack(spacing: 12) {
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
```

**Step 2: Simplify CustomRemindersView rows**

Modify `AthanFramework/Views/CustomRemindersView.swift` — remove the left accent bar from `ReminderRow`. Keep the urgent indicator icon.

Replace the `ReminderRow` body to remove the accent bar:

```swift
// In ReminderRow, remove the leading RoundedRectangle accent bar.
// The body should be:
var body: some View {
    HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(reminder.title)
                    .font(.headline)
                    .foregroundStyle(reminder.isEnabled ? .primary : .secondary)

                if reminder.isUrgent {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Urgent alarm")
                }
            }

            if let time = reminder.scheduledTime {
                Text(DateFormatter.prayerTime.string(from: time))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if reminder.isRecurring && !reminder.recurrenceDays.isEmpty {
                Text(recurrenceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(
                    reminder.isEnabled
                        ? Color(hex: AppConstants.Defaults.tintColorHex)
                        : .secondary
                )
                .symbolEffect(.bounce, value: bellAnimating)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: reminder.isEnabled)
        .accessibilityLabel("\(reminder.title) alarm")
        .accessibilityValue(reminder.isEnabled ? "On" : "Off")
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(reminderAccessibilityLabel)
}
```

Also remove the `accentColor` computed property since we no longer use per-type accent colors for bells.

**Step 3: Build and verify**

Run: `cd /Users/hassan/Documents/claude/athanframework && xcodegen generate && xcodebuild -scheme AthanFramework -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add AthanFramework/Views/PrayerTimesView.swift AthanFramework/Views/CustomRemindersView.swift
git commit -m "refactor: revert prayer times UI to clean native List layout

Remove custom ScrollView/card design. Return to standard iOS List
with sections. Keep per-prayer colored SF Symbol icons, use single
green tint for bell toggles. Remove accent bars from reminder rows."
```

---

## Task 2: Prayer Completion Model + ViewModel

**Files:**
- Create: `AthanFramework/Models/PrayerCompletion.swift`
- Modify: `AthanFramework/Models/CustomReminder.swift`
- Modify: `AthanFramework/ViewModels/PrayerTimesViewModel.swift`
- Modify: `AthanFramework/App/AthanFrameworkApp.swift`

**Step 1: Create PrayerCompletion model**

Create `AthanFramework/Models/PrayerCompletion.swift`:

```swift
import Foundation
import SwiftData

/// Tracks whether a prayer was completed on a given day.
/// Resets daily — each day starts with 5 uncompleted prayers.
@Model
final class PrayerCompletion {
    var id: UUID = UUID()

    /// Normalized to start of day (midnight local time).
    var date: Date = Date()

    /// The raw value of the Prayer enum.
    var prayerName: String = ""

    var isCompleted: Bool = false
    var completedAt: Date?

    init() {}

    convenience init(date: Date, prayer: Prayer) {
        self.init()
        self.date = Calendar.current.startOfDay(for: date)
        self.prayerName = prayer.rawValue
    }
}
```

**Step 2: Add completion fields to CustomReminder**

Modify `AthanFramework/Models/CustomReminder.swift` — add two properties after `calendarEventID`:

```swift
    /// Whether the user has marked this reminder as completed.
    var isCompleted: Bool = false
    var completedAt: Date?
```

**Step 3: Add PrayerCompletion to cloud schema**

Modify `AthanFramework/App/AthanFrameworkApp.swift` — add `PrayerCompletion.self` to the `cloudSchema` array:

```swift
        let cloudSchema = Schema([
            DailyPrayerTimes.self,
            PrayerAlarmConfig.self,
            CustomReminder.self,
            UserPreferences.self,
            PrayerCompletion.self
        ])
```

**Step 4: Add completion methods to PrayerTimesViewModel**

Modify `AthanFramework/ViewModels/PrayerTimesViewModel.swift` — add properties and methods:

Add a new property after `countdownToNext`:

```swift
    var completions: [PrayerCompletion] = []
```

Add these methods after `toggleAlarm(for:)`:

```swift
    /// Load today's completion records, creating missing ones.
    func loadCompletions() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let descriptor = FetchDescriptor<PrayerCompletion>(
            predicate: #Predicate { $0.date >= startOfDay && $0.date < endOfDay }
        )
        var existing = (try? cloudContext.fetch(descriptor)) ?? []

        // Ensure we have a record for every prayer today
        for prayer in Prayer.allCases {
            if !existing.contains(where: { $0.prayerName == prayer.rawValue }) {
                let completion = PrayerCompletion(date: Date(), prayer: prayer)
                cloudContext.insert(completion)
                existing.append(completion)
            }
        }
        try? cloudContext.save()
        completions = existing
    }

    /// Toggle completion state for a prayer.
    func toggleCompletion(for prayer: Prayer) {
        guard let completion = completions.first(where: { $0.prayerName == prayer.rawValue }) else { return }
        completion.isCompleted.toggle()
        completion.completedAt = completion.isCompleted ? Date() : nil
        try? cloudContext.save()
    }

    /// Whether a prayer is completed today.
    func isCompleted(_ prayer: Prayer) -> Bool {
        completions.first(where: { $0.prayerName == prayer.rawValue })?.isCompleted ?? false
    }
```

In `loadTodayTimes()`, add `loadCompletions()` call at the end:

```swift
    func loadTodayTimes() {
        // ... existing code ...
        loadAlarmConfigs()
        loadCompletions()  // ADD THIS LINE
        startCountdownTimer()
    }
```

**Step 5: Build and verify**

Run: `cd /Users/hassan/Documents/claude/athanframework && xcodegen generate && xcodebuild -scheme AthanFramework -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add AthanFramework/Models/PrayerCompletion.swift AthanFramework/Models/CustomReminder.swift AthanFramework/ViewModels/PrayerTimesViewModel.swift AthanFramework/App/AthanFrameworkApp.swift
git commit -m "feat: add prayer completion tracking model

New PrayerCompletion SwiftData model for daily prayer tracking.
Add isCompleted/completedAt to CustomReminder. ViewModel methods
for loading and toggling completion state. Resets daily."
```

---

## Task 3: Completion Circle UI in Prayer & Reminder Rows

**Files:**
- Modify: `AthanFramework/Views/PrayerTimesView.swift`
- Modify: `AthanFramework/Views/CustomRemindersView.swift`
- Modify: `AthanFramework/ViewModels/CustomReminderViewModel.swift`

**Step 1: Add completion circle to PrayerRow**

Modify `PrayerRow` in `PrayerTimesView.swift`:

Add two new parameters after `offsetDescription`:

```swift
    var isCompleted: Bool = false
    var onToggleCompletion: (() -> Void)? = nil
```

In the `PrayerRow` body, add a leading completion button before the SF Symbol icon. Replace the HStack inside the NavigationLink label:

```swift
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
                    // ... rest unchanged
```

Update the `PrayerRow` call site in `prayerCardsSection` (or the `ForEach` in the List Section) to pass completion data:

```swift
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
                            onToggle: { viewModel.toggleAlarm(for: prayer) },
                            onToggleCompletion: { viewModel.toggleCompletion(for: prayer) }
                        )
```

**Step 2: Add completion circle to ReminderRow**

Modify `CustomRemindersView.swift` `ReminderRow`:

Add parameters:

```swift
    var isCompleted: Bool = false
    var onToggleCompletion: (() -> Void)? = nil
```

Add completion button as first item in HStack:

```swift
    var body: some View {
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
                .accessibilityLabel("Mark \(reminder.title) as \(isCompleted ? "incomplete" : "complete")")
            }

            VStack(alignment: .leading, spacing: 4) {
                // ... rest of existing content
```

**Step 3: Add toggleCompletion to CustomReminderViewModel**

Modify `AthanFramework/ViewModels/CustomReminderViewModel.swift` — add method:

```swift
    /// Toggle completion state for a custom reminder.
    func toggleCompletion(_ reminder: CustomReminder) {
        reminder.isCompleted.toggle()
        reminder.completedAt = reminder.isCompleted ? Date() : nil
        try? cloudContext.save()
    }
```

Update the `ReminderRow` call site in `CustomRemindersView` to pass completion:

```swift
                        ReminderRow(
                            reminder: reminder,
                            isCompleted: reminder.isCompleted,
                            onToggle: { viewModel.toggleReminder(reminder) },
                            onToggleCompletion: { viewModel.toggleCompletion(reminder) }
                        )
```

**Step 4: Build and verify**

Run: `cd /Users/hassan/Documents/claude/athanframework && xcodegen generate && xcodebuild -scheme AthanFramework -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add AthanFramework/Views/PrayerTimesView.swift AthanFramework/Views/CustomRemindersView.swift AthanFramework/ViewModels/CustomReminderViewModel.swift
git commit -m "feat: add completion circle toggles to prayer and reminder rows

Apple Reminders-style circle toggle on each prayer and custom
reminder row. Tap to mark as completed (green checkmark) or
incomplete (empty circle). Separate from alarm toggle."
```

---

## Task 4: AlarmKit Live Activity — Widget Extension

**Files:**
- Create: `AthanWidgetExtension/AthanAlarmLiveActivity.swift`
- Create: `AthanWidgetExtension/ReminderAlarmLiveActivity.swift`
- Modify: `AthanWidgetExtension/AthanWidgetBundle.swift`
- Modify: `project.yml`

**Step 1: Create prayer alarm Live Activity**

Create `AthanWidgetExtension/AthanAlarmLiveActivity.swift`:

```swift
import SwiftUI
import WidgetKit
import AlarmKit

/// Live Activity for prayer alarms — shows on lock screen and Dynamic Island.
struct AthanAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<PrayerAlarmMetadata>.self) { context in
            // Lock Screen / StandBy presentation
            LockScreenPrayerView(state: context.state, metadata: context.attributes.metadata)
                .activityBackgroundTint(Color(hex: AppConstants.Defaults.tintColorHex).opacity(0.8))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    if let prayer = Prayer(rawValue: context.attributes.metadata.prayerName) {
                        Image(systemName: prayer.sfSymbol)
                            .font(.title2)
                            .foregroundStyle(Color(hex: prayer.colorHex))
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        if let prayer = Prayer(rawValue: context.attributes.metadata.prayerName) {
                            Text("\(prayer.displayName) Prayer")
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        PrayerCountdownText(state: context.state)
                            .font(.subheadline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PrayerCountdownProgress(state: context.state)
                        .frame(width: 36, height: 36)
                }
            } compactLeading: {
                if let prayer = Prayer(rawValue: context.attributes.metadata.prayerName) {
                    Image(systemName: prayer.sfSymbol)
                        .foregroundStyle(Color(hex: prayer.colorHex))
                }
            } compactTrailing: {
                PrayerCountdownText(state: context.state)
                    .font(.caption)
                    .monospacedDigit()
            } minimal: {
                PrayerCountdownProgress(state: context.state)
            }
        }
    }
}

// MARK: - Lock Screen View

struct LockScreenPrayerView: View {
    let state: AlarmPresentationState
    let metadata: PrayerAlarmMetadata

    var body: some View {
        HStack(spacing: 16) {
            if let prayer = Prayer(rawValue: metadata.prayerName) {
                Image(systemName: prayer.sfSymbol)
                    .font(.largeTitle)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let prayer = Prayer(rawValue: metadata.prayerName) {
                    Text("\(prayer.displayName) Prayer")
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                PrayerCountdownText(state: state)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer()

            PrayerCountdownProgress(state: state)
                .frame(width: 48, height: 48)
        }
        .padding()
    }
}

// MARK: - Countdown Components

struct PrayerCountdownText: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...countdown.fireDate)
                .monospacedDigit()
                .lineLimit(1)
        case .alert:
            Text("Time to pray")
                .fontWeight(.semibold)
                .foregroundStyle(.red)
        @unknown default:
            Text("--:--")
        }
    }
}

struct PrayerCountdownProgress: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            ProgressView(
                timerInterval: Date.now...countdown.fireDate,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .progressViewStyle(.circular)
            .tint(.white)
        case .alert:
            Image(systemName: "bell.and.waves.left.and.right.fill")
                .font(.title3)
                .foregroundStyle(.red)
                .symbolEffect(.variableColor.iterative)
        @unknown default:
            EmptyView()
        }
    }
}
```

**Step 2: Create reminder alarm Live Activity**

Create `AthanWidgetExtension/ReminderAlarmLiveActivity.swift`:

```swift
import SwiftUI
import WidgetKit
import AlarmKit

/// Live Activity for urgent custom reminder alarms.
struct ReminderAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<ReminderAlarmMetadata>.self) { context in
            // Lock Screen presentation
            HStack(spacing: 16) {
                Image(systemName: "bell.badge.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.metadata.reminderTitle)
                        .font(.headline)
                        .foregroundStyle(.white)

                    ReminderCountdownText(state: context.state)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.9))
                }

                Spacer()
            }
            .padding()
            .activityBackgroundTint(.orange.opacity(0.8))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "bell.badge.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.metadata.reminderTitle)
                            .font(.headline)
                            .lineLimit(1)
                        ReminderCountdownText(state: context.state)
                            .font(.subheadline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ReminderCountdownProgress(state: context.state)
                        .frame(width: 36, height: 36)
                }
            } compactLeading: {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                ReminderCountdownText(state: context.state)
                    .font(.caption)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct ReminderCountdownText: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...countdown.fireDate)
                .monospacedDigit()
                .lineLimit(1)
        case .alert:
            Text("Reminder!")
                .fontWeight(.semibold)
                .foregroundStyle(.red)
        @unknown default:
            Text("--:--")
        }
    }
}

struct ReminderCountdownProgress: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            ProgressView(
                timerInterval: Date.now...countdown.fireDate,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .progressViewStyle(.circular)
            .tint(.orange)
        case .alert:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.red)
        @unknown default:
            EmptyView()
        }
    }
}
```

**Step 3: Update AthanWidgetBundle**

Replace `AthanWidgetExtension/AthanWidgetBundle.swift`:

```swift
import WidgetKit
import SwiftUI
import AlarmKit

/// Widget bundle for Athan alarm Live Activities.
@main
struct AthanWidgetBundle: WidgetBundle {
    var body: some Widget {
        AthanAlarmLiveActivity()
        ReminderAlarmLiveActivity()
    }
}
```

**Step 4: Update project.yml — add ReminderAlarmMetadata to widget sources**

In `project.yml`, under `AthanWidgetExtension.sources`, add:

```yaml
      - path: AthanFramework/LiveActivity/ReminderAlarmMetadata.swift
```

**Step 5: Build and verify**

Run: `cd /Users/hassan/Documents/claude/athanframework && xcodegen generate && xcodebuild -scheme AthanFramework -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add AthanWidgetExtension/ project.yml
git commit -m "feat: add AlarmKit Live Activity views for lock screen and Dynamic Island

Prayer and reminder alarm Live Activities with countdown timer,
progress ring, and Dynamic Island compact/expanded/minimal views.
Widget extension now renders alarm UI on lock screen."
```

---

## Task 5: App Icon — Royal Blue with Crescent

**Files:**
- Create: `scripts/generate_icon.swift`
- Modify: `AthanFramework/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`

**Step 1: Create icon generation script**

Create `scripts/generate_icon.swift`:

```swift
#!/usr/bin/env swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let context = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: Int(size) * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("Failed to create context")
    exit(1)
}

// Background: Royal blue gradient
let gradientColors = [
    CGColor(red: 0.102, green: 0.294, blue: 0.549, alpha: 1.0),  // #1A4B8C
    CGColor(red: 0.176, green: 0.357, blue: 0.627, alpha: 1.0)   // #2D5BA0
] as CFArray

guard let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: gradientColors,
    locations: [0.0, 1.0]
) else {
    print("Failed to create gradient")
    exit(1)
}

context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)

// Crescent moon
let moonCenter = CGPoint(x: size * 0.48, y: size * 0.42)
let moonRadius: CGFloat = size * 0.28
let cutoutOffset: CGFloat = size * 0.14

// Full circle for moon
context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
context.addArc(
    center: moonCenter,
    radius: moonRadius,
    startAngle: 0,
    endAngle: .pi * 2,
    clockwise: false
)
context.fillPath()

// Cut out the inner circle to create crescent shape
context.setBlendMode(.clear)
let cutoutCenter = CGPoint(x: moonCenter.x + cutoutOffset, y: moonCenter.y - cutoutOffset * 0.3)
context.addArc(
    center: cutoutCenter,
    radius: moonRadius * 0.82,
    startAngle: 0,
    endAngle: .pi * 2,
    clockwise: false
)
context.fillPath()

context.setBlendMode(.normal)

// Star near the crescent
let starCenter = CGPoint(x: size * 0.62, y: size * 0.28)
let starRadius: CGFloat = size * 0.04
context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9))

// Simple 4-point star
let starPath = CGMutablePath()
starPath.move(to: CGPoint(x: starCenter.x, y: starCenter.y - starRadius))
starPath.addLine(to: CGPoint(x: starCenter.x + starRadius * 0.3, y: starCenter.y - starRadius * 0.3))
starPath.addLine(to: CGPoint(x: starCenter.x + starRadius, y: starCenter.y))
starPath.addLine(to: CGPoint(x: starCenter.x + starRadius * 0.3, y: starCenter.y + starRadius * 0.3))
starPath.addLine(to: CGPoint(x: starCenter.x, y: starCenter.y + starRadius))
starPath.addLine(to: CGPoint(x: starCenter.x - starRadius * 0.3, y: starCenter.y + starRadius * 0.3))
starPath.addLine(to: CGPoint(x: starCenter.x - starRadius, y: starCenter.y))
starPath.addLine(to: CGPoint(x: starCenter.x - starRadius * 0.3, y: starCenter.y - starRadius * 0.3))
starPath.closeSubpath()
context.addPath(starPath)
context.fillPath()

// Small alarm bell at bottom
let bellY: CGFloat = size * 0.72
let bellX: CGFloat = size * 0.5
let bellWidth: CGFloat = size * 0.14
let bellHeight: CGFloat = size * 0.12

context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.6))

// Bell body (rounded trapezoid shape)
let bellPath = CGMutablePath()
bellPath.move(to: CGPoint(x: bellX - bellWidth * 0.3, y: bellY - bellHeight))
bellPath.addLine(to: CGPoint(x: bellX + bellWidth * 0.3, y: bellY - bellHeight))
bellPath.addQuadCurve(
    to: CGPoint(x: bellX + bellWidth * 0.5, y: bellY),
    control: CGPoint(x: bellX + bellWidth * 0.5, y: bellY - bellHeight * 0.5)
)
bellPath.addLine(to: CGPoint(x: bellX - bellWidth * 0.5, y: bellY))
bellPath.addQuadCurve(
    to: CGPoint(x: bellX - bellWidth * 0.3, y: bellY - bellHeight),
    control: CGPoint(x: bellX - bellWidth * 0.5, y: bellY - bellHeight * 0.5)
)
bellPath.closeSubpath()
context.addPath(bellPath)
context.fillPath()

// Bell clapper (small circle at bottom)
context.addArc(
    center: CGPoint(x: bellX, y: bellY + bellHeight * 0.15),
    radius: bellWidth * 0.12,
    startAngle: 0,
    endAngle: .pi * 2,
    clockwise: false
)
context.fillPath()

// Bell handle (small arc on top)
context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.6))
context.setLineWidth(size * 0.012)
context.addArc(
    center: CGPoint(x: bellX, y: bellY - bellHeight - size * 0.01),
    radius: bellWidth * 0.12,
    startAngle: .pi,
    endAngle: 0,
    clockwise: false
)
context.strokePath()

// Save as PNG
guard let image = context.makeImage() else {
    print("Failed to create image")
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.png"

let url = URL(fileURLWithPath: outputPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    print("Failed to create image destination")
    exit(1)
}

CGImageDestinationAddImage(dest, image, nil)

if CGImageDestinationFinalize(dest) {
    print("Icon saved to \(outputPath)")
} else {
    print("Failed to save icon")
    exit(1)
}
```

**Step 2: Generate the icon**

Run: `cd /Users/hassan/Documents/claude/athanframework && swift scripts/generate_icon.swift AthanFramework/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`

Expected: "Icon saved to ..."

**Step 3: Build and verify**

Run: `cd /Users/hassan/Documents/claude/athanframework && xcodegen generate && xcodebuild -scheme AthanFramework -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add scripts/generate_icon.swift AthanFramework/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
git commit -m "feat: new royal blue app icon with crescent moon and bell

Royal blue gradient background (#1A4B8C to #2D5BA0) with white
crescent moon, star, and subtle alarm bell. Clean and Apple-like.
Generated via CoreGraphics script for reproducibility."
```

---

## Task 6: Final Cleanup + OnboardingView

**Files:**
- Modify: `AthanFramework/Views/OnboardingView.swift`

**Step 1: Revert OnboardingView non-welcome changes**

The welcome step gradient is fine. Revert the `completeStep` to remove excessive glow effect — keep the prayer icons strip but simplify:

The current OnboardingView is acceptable. Only minor change: ensure the complete step uses the standard tint color and the prayer icon strip stays.

No changes needed unless the build reveals issues.

**Step 2: Final build on device**

Run: `cd /Users/hassan/Documents/claude/athanframework && xcodegen generate && xcodebuild -scheme AthanFramework -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

**Step 3: Tag and push**

```bash
git tag v1.1-ui-live-activity
git push origin main --tags
```
