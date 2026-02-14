# CLAUDE.md

## Reference Projects

- **AlarmKit sample:** `~/Downloads/SchedulingAnAlarmWithAlarmKit` — Apple's reference implementation for scheduling alarms with AlarmKit. Use this as the source of truth for AlarmKit API patterns, Live Activity integration, and widget extension setup.

## V2 Redesign

- **Design doc:** `docs/plans/2026-02-14-athan-v2-design.md` — UI, Live Activities, completion tracking, Dynamic Island, app icon
- **Implementation plan:** `docs/plans/2026-02-14-athan-v2-plan.md` — 6 tasks with step-by-step code
- **V1 revert point:** Branch `v1-stable` / Tag `v1.0` — full V1 snapshot before V2 work

## Pending Reversions

### Revert iCloud/CloudKit when paid developer account is approved
- **File:** `AthanFramework/App/AthanFrameworkApp.swift` line ~33
- **Change:** `cloudKitDatabase: .none` back to `cloudKitDatabase: .automatic`
- **File:** `AthanFramework/AthanFramework.entitlements`
- **Restore iCloud entitlements:**
  ```xml
  <key>com.apple.developer.icloud-container-identifiers</key>
  <array>
      <string>iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  </array>
  <key>com.apple.developer.icloud-services</key>
  <array>
      <string>CloudKit</string>
  </array>
  ```
- **Why removed:** Free/personal Apple Developer accounts don't support iCloud entitlements. Removed to allow deployment to physical device while paid account approval is pending.
