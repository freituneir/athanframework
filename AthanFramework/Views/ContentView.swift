import SwiftUI
import SwiftData

/// Root view: shows onboarding if first launch, otherwise the main tab interface.
struct ContentView: View {
    @Environment(\.modelContext) private var cloudContext
    @Query private var preferences: [UserPreferences]

    var body: some View {
        Group {
            if preferences.first?.onboardingCompleted == true {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: preferences.first?.onboardingCompleted)
    }
}

/// Tab-based navigation: Today, Reminders, Settings.
struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max.fill") {
                PrayerTimesView()
            }
            Tab("Reminders", systemImage: "bell.badge") {
                CustomRemindersView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tint(AthanTheme.accent)
        .preferredColorScheme(.dark)
    }
}
