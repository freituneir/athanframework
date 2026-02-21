import Foundation
import ActivityKit

/// Standalone ActivityKit attributes for the "Pray Now" Live Activity.
/// Completely independent of AlarmKit — no alarm, no sound, no dismiss/snooze.
/// Only killed by tapping Done or marking the prayer complete in the app.
struct PrayNowAttributes: ActivityAttributes {
    /// The raw value of the `Prayer` enum (e.g., "fajr").
    let prayerName: String
    /// The actual prayer time from the API (no user offset) — used for count-up timer.
    let rawPrayerTime: Date

    struct ContentState: Codable, Hashable {
        /// Always true while the activity is live. Set to false when ending.
        var isActive: Bool = true
    }
}
