import SwiftUI
import SwiftData

@main
struct AthanFrameworkApp: App {
    let cloudContainer: ModelContainer
    let localContainer: ModelContainer

    // Services (created once, injected into the environment)
    let locationService: LocationService
    let calendarService: CalendarService
    let alarmService: AlarmSchedulingService
    let prayerTimeService: PrayerTimeService
    let coordinator: AppCoordinator

    // ViewModels
    let prayerTimesViewModel: PrayerTimesViewModel
    let settingsViewModel: SettingsViewModel
    let onboardingViewModel: OnboardingViewModel
    let customReminderViewModel: CustomReminderViewModel

    init() {
        // NOTE: cloudKitDatabase changed from .automatic to .none to allow
        // deployment on free/personal developer accounts (no iCloud entitlement).
        // Revert to .automatic once paid Apple Developer account is approved.
        let cloudSchema = Schema([
            DailyPrayerTimes.self,
            PrayerAlarmConfig.self,
            CustomReminder.self,
            UserPreferences.self
        ])
        let cloudConfig = ModelConfiguration(
            "CloudStore",
            schema: cloudSchema,
            cloudKitDatabase: .none
        )

        // Local-only models (device-specific alarm IDs, cached prayer times)
        let localSchema = Schema([
            DeviceAlarmState.self
        ])
        let localConfig = ModelConfiguration(
            "LocalStore",
            schema: localSchema,
            cloudKitDatabase: .none
        )

        let cloud: ModelContainer
        let local: ModelContainer
        do {
            cloud = try ModelContainer(for: cloudSchema, configurations: [cloudConfig])
            local = try ModelContainer(for: localSchema, configurations: [localConfig])
        } catch {
            fatalError("Failed to initialize ModelContainers: \(error)")
        }
        self.cloudContainer = cloud
        self.localContainer = local

        // Create contexts
        let cloudContext = ModelContext(cloud)
        let localContext = ModelContext(local)

        // Create services
        let location = LocationService()
        let calendar = CalendarService()
        let alarm = AlarmSchedulingService(localContainer: local)
        let prayerTime = PrayerTimeService(modelContext: cloudContext)
        let coord = AppCoordinator(
            prayerTimeService: prayerTime,
            alarmService: alarm,
            calendarService: calendar,
            locationService: location,
            cloudContext: cloudContext,
            localContext: localContext
        )

        self.locationService = location
        self.calendarService = calendar
        self.alarmService = alarm
        self.prayerTimeService = prayerTime
        self.coordinator = coord

        // Create ViewModels
        self.prayerTimesViewModel = PrayerTimesViewModel(coordinator: coord, cloudContext: cloudContext)
        self.settingsViewModel = SettingsViewModel(cloudContext: cloudContext)
        self.onboardingViewModel = OnboardingViewModel(
            locationService: location,
            alarmService: alarm,
            calendarService: calendar,
            cloudContext: cloudContext
        )
        self.customReminderViewModel = CustomReminderViewModel(
            cloudContext: cloudContext,
            calendarService: calendar,
            alarmService: alarm
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(prayerTimesViewModel)
                .environment(settingsViewModel)
                .environment(onboardingViewModel)
                .environment(customReminderViewModel)
                .environment(locationService)
                .environment(calendarService)
        }
        .modelContainer(cloudContainer)
    }
}
