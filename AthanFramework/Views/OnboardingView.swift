import SwiftUI

/// Multi-step onboarding: welcome -> location -> AlarmKit -> calendar -> calculation method -> complete.
struct OnboardingView: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    /// Total number of steps (excluding welcome and complete screens).
    private let totalSteps = 4

    /// Current progress (0.0 to 1.0) for the progress bar.
    private var progress: Double {
        let step = viewModel.currentStep.rawValue
        guard step > 0 else { return 0 }
        return min(Double(step) / Double(totalSteps), 1.0)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar (hidden on welcome screen)
                if viewModel.currentStep != .welcome && viewModel.currentStep != .complete {
                    ProgressView(value: progress)
                        .tint(AthanTheme.accent)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .accessibilityLabel("Onboarding progress")
                        .accessibilityValue("Step \(viewModel.currentStep.rawValue) of \(totalSteps)")
                        .transition(.opacity)
                }

                Spacer()

                // Step content with transitions
                Group {
                    switch viewModel.currentStep {
                    case .welcome:
                        welcomeStep
                    case .location:
                        locationStep
                    case .alarmKit:
                        alarmKitStep
                    case .calendar:
                        calendarStep
                    case .calculationMethod:
                        calculationMethodStep
                    case .complete:
                        completeStep
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer()
            }
            .padding()
            .animation(.easeInOut(duration: 0.35), value: viewModel.currentStep)
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "moon.stars.fill")
                .font(.system(size: 80))
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .white.opacity(0.3), radius: 20)
                .symbolEffect(.pulse, options: .repeating)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Athan")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Never miss a prayer with system-level alarms that break through Silent Mode and Focus.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                viewModel.nextStep()
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(Color(hex: "#1A2D5A"))
            .controlSize(.large)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: viewModel.currentStep)
            .accessibilityHint("Begin setup")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "#1A2D5A"),
                    Color(hex: "#1B7A3D").opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Permission Steps

    private var locationStep: some View {
        PermissionStepView(
            icon: "location.fill",
            title: "Location Access",
            description: "Your location is used to calculate accurate prayer times for where you are. Location data stays on your device.",
            isGranted: viewModel.locationGranted,
            isProcessing: viewModel.isProcessing,
            onRequest: { await viewModel.requestLocationPermission() },
            onNext: { viewModel.nextStep() }
        )
    }

    private var alarmKitStep: some View {
        PermissionStepView(
            icon: "alarm.fill",
            title: "Alarm Access",
            description: "Alarms break through Silent Mode and Focus to ensure you never miss a prayer. They appear as full-screen alarms, just like your morning alarm.",
            isGranted: viewModel.alarmKitGranted,
            isProcessing: viewModel.isProcessing,
            onRequest: { await viewModel.requestAlarmKitPermission() },
            onNext: { viewModel.nextStep() }
        )
    }

    private var calendarStep: some View {
        PermissionStepView(
            icon: "calendar",
            title: "Calendar Access",
            description: "Prayer times appear on your calendar so you can plan your day around them. This is optional.",
            isGranted: viewModel.calendarGranted,
            isProcessing: viewModel.isProcessing,
            isOptional: true,
            onRequest: { await viewModel.requestCalendarPermission() },
            onNext: { viewModel.nextStep() }
        )
    }

    // MARK: - Calculation Method

    private var calculationMethodStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "function")
                .font(.system(size: 48))
                .foregroundStyle(AthanTheme.accent.gradient)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Calculation Method")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Choose the method used to calculate prayer times in your region.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                Picker("Method", selection: Binding(
                    get: { viewModel.selectedMethod },
                    set: { viewModel.selectedMethod = $0 }
                )) {
                    ForEach(CalculationMethod.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .pickerStyle(.wheel)
                .accessibilityLabel("Calculation method")
                .sensoryFeedback(.selection, trigger: viewModel.selectedMethod)

                Picker("Asr School", selection: Binding(
                    get: { viewModel.selectedSchool },
                    set: { viewModel.selectedSchool = $0 }
                )) {
                    ForEach(AsrSchool.allCases) { school in
                        Text(school.displayName).tag(school)
                    }
                }
                .accessibilityLabel("Asr juristic school")
                .sensoryFeedback(.selection, trigger: viewModel.selectedSchool)
            }

            Spacer()

            Button {
                viewModel.nextStep()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AthanTheme.accent)
            .controlSize(.large)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: viewModel.currentStep)
        }
    }

    // MARK: - Complete

    private var completeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                // Soft glow behind the checkmark
                Circle()
                    .fill(AthanTheme.accent.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(AthanTheme.accent.gradient)
                    .symbolEffect(.bounce, options: .nonRepeating)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 12) {
                Text("You're All Set")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Prayer alarms are ready. They'll fire as full-screen alarms that persist until you tap Done.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Prayer icons strip
            HStack(spacing: 16) {
                ForEach(Prayer.allCases) { prayer in
                    Image(systemName: prayer.sfSymbol)
                        .font(.title3)
                        .foregroundStyle(Color(hex: prayer.colorHex))
                }
            }
            .padding(.top, 8)
            .accessibilityHidden(true)

            Spacer()

            Button {
                viewModel.completeOnboarding()
            } label: {
                Text("Start Using Athan")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AthanTheme.accent)
            .controlSize(.large)
            .sensoryFeedback(.success, trigger: viewModel.currentStep)
            .accessibilityHint("Complete setup and open the app")
        }
    }
}

// MARK: - Permission Step Component

/// Reusable permission request step with consistent layout and accessibility.
struct PermissionStepView: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    var isProcessing: Bool = false
    var isOptional: Bool = false
    let onRequest: () async -> Void
    let onNext: () -> Void

    @State private var didGrant = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(AthanTheme.accent.gradient)
                .symbolEffect(.bounce, value: isGranted)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(description)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if isGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AthanTheme.accent)
                    .font(.headline)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("\(title) permission granted")

                Button {
                    onNext()
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AthanTheme.accent)
                .controlSize(.large)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Button {
                    Task { await onRequest() }
                } label: {
                    Group {
                        if isProcessing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Allow \(title)")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AthanTheme.accent)
                .controlSize(.large)
                .disabled(isProcessing)
                .accessibilityHint("Opens system permission dialog for \(title.lowercased())")

                if isOptional {
                    Button("Skip") {
                        onNext()
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .accessibilityHint("Continue without granting \(title.lowercased()) permission")
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isGranted)
        .sensoryFeedback(.success, trigger: isGranted)
    }
}
