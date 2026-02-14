import Foundation
import SwiftData

/// ViewModel for the multi-step onboarding flow.
/// Guides the user through: location → AlarmKit → calendar permissions, then initial setup.
@Observable
@MainActor
final class OnboardingViewModel {
    private let locationService: LocationService
    private let alarmService: AlarmSchedulingService
    private let calendarService: CalendarService
    private let cloudContext: ModelContext

    enum Step: Int, CaseIterable {
        case welcome
        case location
        case alarmKit
        case calendar
        case calculationMethod
        case complete
    }

    var currentStep: Step = .welcome
    var locationGranted = false
    var alarmKitGranted = false
    var calendarGranted = false
    var selectedMethod: CalculationMethod = .isna
    var selectedSchool: AsrSchool = .shafi
    var isProcessing = false

    init(
        locationService: LocationService,
        alarmService: AlarmSchedulingService,
        calendarService: CalendarService,
        cloudContext: ModelContext
    ) {
        self.locationService = locationService
        self.alarmService = alarmService
        self.calendarService = calendarService
        self.cloudContext = cloudContext
    }

    func requestLocationPermission() async {
        isProcessing = true
        locationService.requestPermission()
        // Give the system a moment to show the dialog
        try? await Task.sleep(for: .seconds(1))
        locationGranted = locationService.authorizationStatus == .authorizedWhenInUse
            || locationService.authorizationStatus == .authorizedAlways
        isProcessing = false
    }

    func requestAlarmKitPermission() async {
        isProcessing = true
        do {
            alarmKitGranted = try await alarmService.requestAuthorization()
            print("[Onboarding] AlarmKit granted: \(alarmKitGranted)")
        } catch {
            print("[Onboarding] AlarmKit authorization FAILED: \(error)")
            alarmKitGranted = false
        }
        isProcessing = false
    }

    func requestCalendarPermission() async {
        isProcessing = true
        calendarGranted = (try? await calendarService.requestAccess()) ?? false
        isProcessing = false
    }

    func completeOnboarding() {
        let descriptor = FetchDescriptor<UserPreferences>()
        let prefs = (try? cloudContext.fetch(descriptor).first) ?? UserPreferences()
        if prefs.modelContext == nil {
            cloudContext.insert(prefs)
        }
        prefs.calculationMethod = selectedMethod
        prefs.school = selectedSchool
        prefs.calendarSyncEnabled = calendarGranted
        prefs.onboardingCompleted = true
        try? cloudContext.save()
    }

    func nextStep() {
        guard let nextIndex = Step(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = nextIndex
    }
}
