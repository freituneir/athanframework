# Roadmap

## Next Up

### Actual Athan Sounds
Add authentic athan (call to prayer) audio files for alarm sounds. Replace silent/system sound placeholders with real athan recitations. Include multiple reciter options (e.g., Makkah, Madinah styles) and allow the user to pick their preferred reciter per prayer.

### Full UI Redesign
Complete visual overhaul of the application. Rethink navigation, prayer time display, settings layout, and overall aesthetic. Focus on a modern, immersive Islamic design language while maintaining native iOS feel.

### Live Activity — Lock Screen Widget
Persistent Live Activity showing the next prayer time countdown directly on the iPhone Lock Screen and Dynamic Island throughout the day. Unlike the alarm-triggered widget (which only appears when an alarm fires), this would be an always-visible countdown that updates in real-time.

- Show current/next prayer name + time remaining
- Dynamic Island compact view with countdown
- Auto-advance to the next prayer after each one passes
- Start automatically on app launch, end at Isha

### Home Screen Widget
A static/timeline-based WidgetKit widget for the Home Screen and StandBy. Shows today's prayer times at a glance without opening the app.

- Small: next prayer name + countdown
- Medium: all 5 prayer times with highlights for next/passed
- Large: full day view with Hijri date, location, and completion status
- Configurable tint color and calculation method

## Technical Notes

### The Practical Path to Replicating Urgent Reminders Behavior

A third-party developer who wants their app's tasks to appear in the Calendar and also trigger alarm-style alerts must use both frameworks in parallel. The approach works as follows:

**Step 1 — Create an EventKit reminder for Calendar visibility.** Use `EKEventStore` to create an `EKReminder` with `dueDateComponents` set to the target date and time. This reminder will automatically appear in both Apple's Reminders app and the Calendar app (on iOS 18+ with "Scheduled Reminders" enabled, which is the default). The `EKReminder.priority` property accepts integer values 0–9, mapping to none, high (1–4), medium (5), and low (6–9) — but setting high priority does not trigger alarm behavior. Priority is purely cosmetic metadata that shows exclamation marks in the Reminders app.

**Step 2 — Schedule an AlarmKit alarm for the same time.** Use `AlarmManager.shared.schedule(id:configuration:)` to create a system-level alarm that fires at the same moment as the reminder's due date. This alarm will break through Silent Mode and Focus, present a full-screen alert, and support snooze/stop controls with custom actions.

**Step 3 — Synchronize state between the two.** When the user stops or snoozes the alarm (via App Intents callbacks), update the EventKit reminder accordingly — mark it complete, reschedule it, or leave it as-is depending on app logic. This coordination logic must be developer-implemented since there is no system-level link between the two.

This two-framework approach replicates the functional behavior of Urgent Reminders — a task visible in Calendar that triggers a real alarm — even though it cannot set the actual "Urgent" flag that Apple's Reminders app uses internally.

## Future Ideas

- Apple Watch companion
- Qibla compass
- Hijri calendar integration
- Prayer tracking / streak stats
