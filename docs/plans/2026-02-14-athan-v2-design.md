# Athan v2 Design: UI, Live Activities, Completion, Dynamic Island, Icon

## Decision Log
- Completion tracking: **Resets daily** (fresh 5 circles each morning)
- App icon color: **Royal blue (#1A4B8C)**
- UI approach: Revert to native `List`, enhance selectively
- Live Activity: Widget extension `ActivityConfiguration` with `AlarmAttributes`

---

## 1. UI Redesign

### Problem
Previous redesign used custom ScrollView + gradient cards + per-prayer colored bells. Made everything dimmer, cluttered, and un-iOS-like.

### Solution
Revert to standard `List`-based layout. Apple's own apps (Clock, Reminders, Health) use `List` with `Section` because it provides native styling, swipe actions, inertia, and separators for free.

### Layout
- **Header section**: Location name (`.headline`), Hijri date (`.subheadline .secondary`)
- **Countdown section**: "Next: Fajr" with large countdown text
- **Prayer section**: `ForEach(Prayer.allCases)` with clean rows:
  - Leading: completion circle (empty/filled green)
  - SF Symbol icon (per-prayer color — ONLY the icon)
  - Prayer name + time
  - Trailing: bell toggle (single green tint `#1B7A3D`, never per-prayer colors)
  - Offset caption below bell when applicable
- **Sunrise row**: Inline between Fajr and Dhuhr, orange icon, no toggle, no navigation

### Colors
- Bell toggles: always `#1B7A3D` (app green) when enabled
- SF Symbol icons: per-prayer `colorHex` (fajr=indigo, dhuhr=blue, etc.)
- Completion circles: green when checked
- Backgrounds: system defaults (no custom cards)

---

## 2. AlarmKit Live Activity (Widget Extension)

### Problem
`AthanWidgetBundle` has an empty body. No `ActivityConfiguration` means no Live Activity renders on lock screen or Dynamic Island.

### Solution
Add two `ActivityConfiguration` declarations:

```
AthanWidgetBundle {
    AthanAlarmLiveActivity()       // for: AlarmAttributes<PrayerAlarmMetadata>
    ReminderAlarmLiveActivity()    // for: AlarmAttributes<ReminderAlarmMetadata>
}
```

### Lock Screen View
- Prayer/reminder name (title)
- Countdown timer: `Text(timerInterval: now...fireDate)` during `.countdown`
- "Time to pray" message during `.alert`
- Prayer SF Symbol icon

### Dynamic Island
- **Expanded**: Prayer name + countdown + progress bar
- **Compact leading**: Prayer icon
- **Compact trailing**: Countdown text
- **Minimal**: Circular progress

### Overdue Indicator (post-alert)
- When `.alert` mode: show elapsed time since fire in **red**
- Compact trailing: red "5m" text
- Minimal: red dot

### project.yml Changes
Add `ReminderAlarmMetadata.swift` to widget extension sources.

---

## 3. Prayer Completion Tracking

### New Model: `PrayerCompletion`
```swift
@Model
final class PrayerCompletion {
    var date: Date      // normalized to start of day
    var prayerName: String
    var isCompleted: Bool = false
    var completedAt: Date?
}
```

### Custom Reminder Completion
Add to `CustomReminder`:
- `isCompleted: Bool = false`
- `completedAt: Date?`

### UI
- Leading circle button on each prayer row (like Apple Reminders)
- Empty circle `circle` -> filled `checkmark.circle.fill` in green
- Same pattern on custom reminder rows
- Completion is separate from alarm (alarm fires regardless)

### Reset Behavior
Completions are keyed by date. Each new day starts with no completions. Old records can be cleaned up periodically.

---

## 4. Dynamic Island Elapsed Time

Handled entirely in widget extension views (see section 2). During `.alert` state, compute elapsed time from `countdown.fireDate` and display in red tint.

---

## 5. App Icon

### Design
- Background: Royal blue gradient (#1A4B8C to #2D5BA0)
- Foreground: White crescent moon + subtle alarm bell silhouette
- Style: Clean, minimal, pseudo-3D with subtle shadows
- Size: 1024x1024 PNG
- Generated programmatically via CoreGraphics Swift script

---

## Files Changed

| File | Change |
|------|--------|
| `Views/PrayerTimesView.swift` | Revert to List, add completion circles |
| `Views/CustomRemindersView.swift` | Simplify rows, add completion circles |
| `Views/OnboardingView.swift` | Keep welcome gradient, minor cleanup |
| `Models/PrayerCompletion.swift` (NEW) | Daily completion tracking model |
| `Models/CustomReminder.swift` | +isCompleted, +completedAt |
| `ViewModels/PrayerTimesViewModel.swift` | +completion toggle, cleanup |
| `AthanWidgetBundle.swift` | +ActivityConfiguration for prayer + reminder |
| `AthanWidgetExtension/AthanAlarmLiveActivity.swift` (NEW) | Prayer alarm Live Activity views |
| `AthanWidgetExtension/ReminderAlarmLiveActivity.swift` (NEW) | Reminder alarm Live Activity views |
| `project.yml` | Add ReminderAlarmMetadata to widget sources |
| `App/AthanFrameworkApp.swift` | Add PrayerCompletion to schema |
| `AppIcon.png` | New blue icon |
