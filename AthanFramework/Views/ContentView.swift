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
/// Uses @AppStorage to reactively re-render when the theme changes.
struct MainTabView: View {
    @AppStorage(AppConstants.AppGroup.themeKey, store: UserDefaults(suiteName: AppConstants.AppGroup.suiteName))
    private var themeRaw: String = ColorTheme.green.rawValue

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
        .id(themeRaw)
        .tint(AthanTheme.accent)
        .preferredColorScheme(.dark)
    }
}
