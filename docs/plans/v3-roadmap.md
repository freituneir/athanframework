# Athan v3 Roadmap

Future feature ideas beyond v2.

---

## 1. Missed Prayer Reminder Alarms

**Priority:** High

If a prayer hasn't been marked as completed yet, schedule an additional reminder alarm **30 minutes before the next prayer** to nudge the user to pray.

### Behavior
- After each prayer's athan alarm fires, the system monitors whether the user marks it as done (via the completion toggle)
- If the prayer remains unmarked ~30 minutes before the **next** prayer time, fire a secondary "reminder" alarm
- Example: Dhuhr athan fires at 12:15. If by ~3:00 PM (30 min before Asr at 3:30), Dhuhr is still unmarked, fire a reminder alarm
- The reminder should have a distinct tone or label (e.g., "Dhuhr — Don't forget to pray") so the user knows it's a reminder, not a new athan
- Isha has no "next prayer" the same day — use a configurable fallback window (e.g., 2 hours after Isha)

### Technical Considerations
- Requires checking `PrayerCompletion` state when scheduling alarms
- Could use `AlarmKit` with a separate `ReminderAlarmMetadata` type to distinguish from regular athan alarms
- The 30-minute window should be configurable in Settings (e.g., 15 / 30 / 45 min before next prayer)
- Need to cancel the reminder if the user marks the prayer as done before the window
- Background refresh or AlarmKit `postAlert` callback could trigger the check

### Open Questions
- Should this be opt-in or on by default?
- Should it fire as a full alarm (sound + Live Activity) or a quieter notification?
- What happens if the user has alarm offsets configured? (Reminder timing should respect those)
