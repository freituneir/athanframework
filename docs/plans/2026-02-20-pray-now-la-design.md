# Standalone "Pray Now" Live Activity — Decoupled from AlarmKit

## Context

The "Pray Now" LA has been unreliable because it's tied to the AlarmKit alarm lifecycle. When AlarmKit's `stop()`, `cancel()`, or hardware dismiss kills the alarm, the LA dies with it. We've spent 3 iterations trying to work around this coupling. The user's requirement is simple: **if prayer time has passed and prayer is not done, show a count-up LA. Period.**

The fix: use **standalone ActivityKit** (`Activity.request()`) for the "Pray Now" LA, completely separate from AlarmKit. Two independent systems:
- **AlarmKit** handles the sound alarm + pre-alert countdown LA (fires, snooze, dismiss — we don't care what happens to it)
- **ActivityKit** handles the persistent "Pray Now" count-up LA (only killed by tapping Done)

## Design

### New: `PrayNowAttributes` (ActivityKit, no AlarmKit)

A custom `ActivityAttributes` struct for the standalone "Pray Now" LA:
```swift
struct PrayNowAttributes: ActivityAttributes {
    let prayerName: String        // "fajr", "dhuhr", etc.
    let rawPrayerTime: Date       // actual prayer time (for count-up)

    struct ContentState: Codable, Hashable {
        var isActive: Bool        // always true until ended
    }
}
```

This is NOT an `AlarmAttributes` — it's plain ActivityKit. No alarm, no sound, no dismiss/snooze. Just a persistent widget on the lock screen.

### New: `PrayNowLiveActivity` (Widget Configuration)

A new `ActivityConfiguration(for: PrayNowAttributes.self)` in the widget bundle. Renders:
- Lock screen: "[Prayer] — Pray Now" + count-up timer from `rawPrayerTime` + Done button
- Dynamic Island compact: prayer name + prayer icon
- Dynamic Island expanded: same as lock screen

The Done button uses an `AppIntent` (new `MarkPrayerDoneIntent`) that:
1. Writes completion to App Group
2. Calls `Activity.end()` on this specific activity

### Scheduling: Pre-scheduled at reconcile time

During `reconcileAlarms()`, for each prayer:
1. Schedule the AlarmKit alarm as before (sound + countdown LA)
2. **Also** call `Activity.request()` for a `PrayNowAttributes` LA, scheduled to appear at `prayerTime` (or `prayerTime + 30s` to avoid overlap with the alarm's countdown LA)

**Key constraint:** `Activity.request()` must be called from the foreground. Since `reconcileAlarms()` runs on foreground return and on pull-to-refresh, this is always satisfied.

**`Activity.request()` supports `staleDate`** — we can set it far in the future (8 hours) so iOS doesn't prematurely remove it.

### Lifecycle

```
reconcileAlarms() runs (foreground):
  → AlarmKit: schedule alarm for prayer (sound + countdown LA)
  → ActivityKit: Activity.request() for PrayNowAttributes at prayerTime

Prayer time arrives:
  → AlarmKit fires alarm, shows countdown→alert LA (sound plays)
  → ActivityKit: "Pray Now" LA appears on lock screen (independently!)

User interacts with alarm (dismiss/snooze/hardware):
  → AlarmKit LA may live or die — we don't care
  → "Pray Now" ActivityKit LA is UNTOUCHED — different system entirely

User taps Done on "Pray Now" LA:
  → MarkPrayerDoneIntent runs
  → Writes completion to App Group
  → Activity.end() kills this specific LA
  → On next foreground, app syncs completion from App Group

User marks done in app:
  → toggleCompletion() ends the Activity
  → Also cancels AlarmKit alarm
```

### What about the AlarmKit LA?

The AlarmKit alarm's countdown LA (the one showing "Fajr in 4:30") still exists for the pre-alert phase. Once the alarm fires, AlarmKit manages that LA's lifecycle. We stop caring about it. If it persists after dismiss — fine, iOS stacks them. If AlarmKit kills it — fine, the standalone "Pray Now" LA is still there.

### Tracking active "Pray Now" activities

Store the `Activity<PrayNowAttributes>.id` in a dictionary keyed by prayer name. On reconcile:
- If a "Pray Now" activity already exists for this prayer and the prayer is NOT completed → skip (don't create a duplicate)
- If the prayer IS completed → end the activity
- If no activity exists and prayer time is in the future → schedule one

### Files to Create/Modify

| File | Change |
|------|--------|
| **NEW** `AthanFramework/LiveActivity/PrayNowAttributes.swift` | `ActivityAttributes` struct |
| **NEW** `AthanWidgetExtension/PrayNowLiveActivity.swift` | Widget configuration + views (reuse existing view components) |
| **NEW** `AthanFramework/Intents/PrayNowIntents.swift` | `MarkPrayerDoneIntent` AppIntent |
| `AthanFramework/Services/AlarmSchedulingService.swift` | Add `schedulePrayNowActivity()` / `endPrayNowActivity()` methods |
| `AthanFramework/ViewModels/PrayerTimesViewModel.swift` | Call `endPrayNowActivity()` in `toggleCompletion()` |
| `AthanWidgetExtension/AthanWidgetBundle.swift` | Add `PrayNowLiveActivity()` to bundle |
| `project.yml` | Add new source files to widget extension sources list |

### What to Remove

- `DismissPrayerIntent` followup scheduling (the inline alarm scheduling we just added — no longer needed)
- `scheduleRecoveryAlarm()` — no longer needed (the standalone LA handles this)
- `recoverMissedAlarmIfNeeded()` — no longer needed (the standalone LA is always there)
- `firedAlarms` App Group tracking — no longer needed
- `followupAlarmIDKey` — no longer needed
- All the followup/recovery namespace code from this session

The AlarmKit alarm keeps its `DismissPrayerIntent` with `countdown()` (for snooze cycling), but we stop trying to make it serve as the "Pray Now" widget.

## Verification

1. Build: `xcodegen generate && xcodebuild build`
2. On device:
   - Schedule test alarm → verify countdown LA appears → alarm fires
   - At prayer time: verify "Pray Now" LA appears independently
   - Hardware-dismiss the alarm → verify "Pray Now" LA still there
   - On-screen dismiss → verify "Pray Now" LA still there
   - Snooze → verify "Pray Now" LA still there
   - Tap Done on "Pray Now" LA → verify it disappears
   - Mark done in app → verify "Pray Now" LA disappears
3. Edge cases:
   - Two prayers past and uncompleted → two "Pray Now" LAs stacked
   - App killed and relaunched → reconcile re-evaluates, ends completed, keeps uncompleted
