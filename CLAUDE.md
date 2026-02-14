# CLAUDE.md

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
