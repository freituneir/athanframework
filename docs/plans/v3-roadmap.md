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

---

## 2. Force Re-schedule on Offset Change

**Priority:** High

When the user changes any prayer's offset (e.g., Fajr from 0 to -10 min), all alarms should be stopped and rescheduled immediately with the new offset applied.

### Current Behavior
- Offset changes are saved to the `PrayerAlarmConfig` in SwiftData
- Alarms are only rescheduled on the next `reconcileAlarms()` call (foreground return or pull-to-refresh)
- The non-destructive reconcile may skip prayers that already have an active alarm, meaning the old offset stays in effect until the alarm fires or the app is refreshed

### Desired Behavior
- Changing any prayer offset in Settings triggers: stop all alarms → reconcile immediately
- This ensures the new offset takes effect right away
- The "Pray Now" standalone LAs should also be re-evaluated (prayer time hasn't changed, but the alarm timing has)

### Implementation Notes
- In `SettingsViewModel` (or wherever offset is saved): after saving the new offset, call `alarmService.stopAllAlarms()` then trigger a full `refreshAll()` or `reconcileAlarmsFromCache()`
- Alternatively, just call `cancelAlarm(for: prayer)` for the specific prayer whose offset changed, then let the next reconcile pick it up — but a full stop+reconcile is simpler and safer

---

## 3. Push-to-Start "Pray Now" Live Activity via APNs

**Priority:** Medium (requires paid Apple Developer account + backend server)

### Problem

The standalone "Pray Now" LA uses `Activity.request()` which **must be called from the foreground**. If the user is asleep and dismisses the alarm from the lock screen or via hardware buttons, no "Pray Now" LA appears until they open the app. The gap between alarm dismiss and next app open has no LA on the lock screen.

### Solution: Push-to-Start

iOS 17.2+ supports **push-to-start tokens** — the server can start a new Live Activity remotely via APNs, even when the app is killed. The flow:

1. App registers for push-to-start token on launch (`Activity<PrayNowAttributes>.pushToStartToken`)
2. App sends the token + prayer schedule to the backend
3. Backend stores the token and schedules a push for each prayer time
4. At prayer time, backend sends APNs push → iOS starts the "Pray Now" LA on the device
5. LA persists until user taps Done (which calls `Activity.end()` locally)

This eliminates the foreground requirement entirely — the LA appears automatically at prayer time whether the app is running or not.

### Backend Options (Lightweight)

The backend only needs to: store device tokens, schedule timed pushes, send APNs HTTP/2 requests. No database, no user accounts, no complex logic.

| Option | Pros | Cons |
|--------|------|------|
| **Firebase Cloud Functions + FCM** | Native APNs integration, free tier generous, familiar ecosystem | Google dependency, cold starts |
| **Cloudflare Workers + Cron Triggers** | Edge-based (fast), cheap ($5/mo), cron triggers for scheduling | Must implement APNs HTTP/2 directly, JWT signing |
| **Simple VPS + cron** | Full control, any language | Must maintain server, handle uptime |

Firebase is the path of least resistance — FCM already handles APNs token management and has a built-in scheduler.

### APNs Requirements

- **Paid Apple Developer account** (required for APNs auth keys)
- **APNs auth key (.p8)** — p12 certificates don't work for Live Activity push
- **HTTP/2 + TLS 1.2** connection to `api.push.apple.com`
- **Headers:** `apns-push-type: liveactivity`, `apns-topic: com.athanframework.AthanFramework.push-type.liveactivity`
- **Payload:** must include `attributes-type`, `attributes`, and `content-state` matching `PrayNowAttributes`

### Payload Example

```json
{
  "aps": {
    "timestamp": 1708500000,
    "event": "start",
    "attributes-type": "PrayNowAttributes",
    "attributes": {
      "prayerName": "fajr",
      "rawPrayerTime": 1708500000
    },
    "content-state": {
      "isActive": true
    }
  }
}
```

### App-Side Changes

1. Register for push-to-start token: `for await token in Activity<PrayNowAttributes>.pushToStartTokenUpdates { ... }`
2. Send token + prayer schedule to backend on each reconcile
3. Handle incoming push-started LAs (they appear automatically, Done button already works via `MarkPrayerDoneIntent`)

### Open Questions

- Should the backend recalculate prayer times (using Aladhan API) or trust the schedule sent by the app?
- How to handle timezone changes / travel?
- Should the push also update the LA content (e.g., next prayer info), or keep it simple?
- Rate limiting: Apple limits ~10-15 push updates per hour per LA

### References

- [Apple: Starting and updating Live Activities with ActivityKit push notifications](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
- [Firebase: Get started with Live Activity](https://firebase.google.com/docs/cloud-messaging/customize-messages/live-activity)
- [Server side Live Activities guide (Christian Selig)](https://christianselig.com/2024/09/server-side-live-activities/)
- [APNsPush: Start and Update iOS Live Activities](https://apnspush.com/how-to-start-and-update-live-activities-with-push-notifications)
