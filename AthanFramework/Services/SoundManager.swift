import Foundation
import AlarmKit

/// Utility for discovering and mapping Athan sound files bundled with the app.
enum SoundManager {

    /// Represents an available alarm sound.
    struct AthanSound: Identifiable, Hashable {
        let id: String
        /// File name without extension (matches `PrayerAlarmConfig.soundFileName`).
        let fileName: String
        /// Human-readable name for display in the UI.
        let displayName: String
        /// Optional description for the sound picker.
        let description: String?
    }

    /// Built-in Athan sounds shipped in the app bundle.
    static let availableSounds: [AthanSound] = [
        AthanSound(id: "default_athan", fileName: "default_athan", displayName: "Default Athan", description: "Standard call to prayer"),
        AthanSound(id: "makkah_athan", fileName: "makkah_athan", displayName: "Makkah", description: "Makkah-style adhan"),
        AthanSound(id: "madinah_athan", fileName: "madinah_athan", displayName: "Madinah", description: "Madinah-style adhan"),
        AthanSound(id: "fajr_athan", fileName: "fajr_athan", displayName: "Fajr Athan", description: "Special dawn prayer call"),
        AthanSound(id: "simple_tone", fileName: "simple_tone", displayName: "Simple Tone", description: "Minimal alert tone"),
        AthanSound(id: "default_reminder", fileName: "default_reminder", displayName: "Gentle Reminder", description: "Soft reminder sound"),
    ]

    /// Returns the `AlertConfiguration.AlertSound` for a given file name.
    /// Falls back to `.default` if the file name is empty or not found in the bundle.
    static func alertSound(for fileName: String) -> AlertConfiguration.AlertSound {
        guard !fileName.isEmpty else { return .default }
        return AlertConfiguration.AlertSound.named(fileName)
    }

    /// Looks up the display name for a sound file name. Returns the file name itself if not found.
    static func displayName(for fileName: String) -> String {
        availableSounds.first(where: { $0.fileName == fileName })?.displayName ?? fileName
    }
}
