import SwiftUI
import SwiftData

// MARK: - Main Prayer Times Screen

struct PrayerTimesView: View {
    @Environment(PrayerTimesViewModel.self) private var viewModel
    @Environment(\.scenePhase) private var scenePhase
    @Query private var preferences: [UserPreferences]

    var body: some View {
        NavigationStack {
            ZStack {
                AthanTheme.backgroundGradient.ignoresSafeArea()
                ambientGlows
                GeometricAccentView()
                    .opacity(0.04)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        dateSection
                            .padding(.top, 20)
                            .padding(.bottom, 48)

                        if let next = viewModel.nextPrayer {
                            NextPrayerCard(
                                prayer: next,
                                timeString: viewModel.timeString(for: next),
                                countdown: viewModel.countdownFormatted,
                                progress: viewModel.progressToNextPrayer,
                                allPassed: false,
                                isCompleted: viewModel.isCompleted(next),
                                onDone: { viewModel.toggleCompletion(for: next) }
                            )
                        } else {
                            NextPrayerCard(
                                prayer: .fajr,
                                timeString: viewModel.tomorrowFajrTimeString,
                                countdown: viewModel.countdownFormatted,
                                progress: viewModel.progressToNextPrayer,
                                allPassed: true,
                                isCompleted: false,
                                onDone: {}
                            )
                        }

                        todayPrayersSection
                            .padding(.top, 24)

                        if let error = viewModel.errorMessage {
                            errorView(error)
                        }

                        if viewModel.isLoading && viewModel.todayTimes == nil {
                            loadingView
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 80)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .task {
                viewModel.loadTodayTimes()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(600))
                    await viewModel.refreshIfNeeded()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.loadTodayTimes()
                    Task { await viewModel.refreshIfNeeded() }
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }

    // MARK: - Date Section

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            let now = Date()

            VStack(alignment: .leading, spacing: 0) {
                Text(now.formatted(.dateTime.weekday(.wide)))
                Text(now.formatted(.dateTime.month(.wide).day()))
            }
            .font(.system(size: 48, weight: .light, design: .serif))
            .foregroundStyle(AthanTheme.textPrimary)

            if !viewModel.hijriDate.isEmpty {
                Text(viewModel.hijriDate.uppercased())
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(AthanTheme.accent.opacity(0.6))
                    .tracking(1.5)
                    .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Today's Prayers List

    private var todayPrayersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TODAY\u{2019}S PRAYERS")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AthanTheme.textSecondary)
                .tracking(2)
                .padding(.bottom, 16)

            ForEach(Prayer.allCases) { prayer in
                if prayer != viewModel.nextPrayer {
                    prayerRow(prayer)
                }
            }
        }
    }

    private func prayerRow(_ prayer: Prayer) -> some View {
        let completed = viewModel.isCompleted(prayer)
        let passed = viewModel.hasPassed(prayer)
        let dimmed = completed || passed

        return HStack(spacing: 10) {
            Button {
                viewModel.toggleCompletion(for: prayer)
            } label: {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(completed ? AthanTheme.accent.opacity(0.6) : AthanTheme.textSecondary.opacity(0.35))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: completed)

            NavigationLink {
                PrayerDetailView(prayer: prayer)
            } label: {
                HStack {
                    Text(prayer.displayName)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(dimmed ? AthanTheme.textSecondary.opacity(0.35) : AthanTheme.textSecondary)
                        .strikethrough(completed, color: AthanTheme.textSecondary.opacity(0.2))

                    Spacer()

                    Text(viewModel.timeString(for: prayer))
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(dimmed ? AthanTheme.textSecondary.opacity(0.35) : AthanTheme.textSecondary.opacity(0.75))
                        .monospacedDigit()
                        .strikethrough(completed, color: AthanTheme.textSecondary.opacity(0.2))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.03))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(prayer.displayName), \(viewModel.timeString(for: prayer))\(completed ? ", completed" : passed ? ", passed" : "")")
    }

    // MARK: - Error & Loading

    private func errorView(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.callout)
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.callout)
                    .foregroundStyle(AthanTheme.accent)
            }
        }
        .padding(.top, 24)
    }

    private var loadingView: some View {
        HStack {
            Spacer()
            ProgressView()
                .tint(AthanTheme.accent)
            Text("Loading prayer times...")
                .font(.subheadline)
                .foregroundStyle(AthanTheme.textSecondary)
            Spacer()
        }
        .padding(.top, 24)
    }

    // MARK: - Ambient Glow Background

    private var ambientGlows: some View {
        ZStack {
            RadialGradient(
                colors: [AthanTheme.accent.opacity(0.05), .clear],
                center: UnitPoint(x: 0.7, y: 0.2),
                startRadius: 0,
                endRadius: 300
            )
            RadialGradient(
                colors: [AthanTheme.accentDeep.opacity(0.03), .clear],
                center: UnitPoint(x: 0.2, y: 0.8),
                startRadius: 0,
                endRadius: 250
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Next Prayer Card

private struct NextPrayerCard: View {
    let prayer: Prayer
    let timeString: String
    let countdown: String?
    let progress: Double
    let allPassed: Bool
    let isCompleted: Bool
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: label + sun icon
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(allPassed ? "NEXT PRAYER" : "NEXT PRAYER")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AthanTheme.accent.opacity(0.5))
                        .tracking(2.5)

                    Text(allPassed ? "Fajr" : prayer.displayName)
                        .font(.system(size: 36, weight: .regular, design: .serif))
                        .foregroundStyle(AthanTheme.textPrimary)
                }
                Spacer()
                SunIconView()
                    .frame(width: 52, height: 52)
            }
            .padding(.bottom, 24)

            // Countdown digits
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(countdown ?? "--:--")
                    .font(.system(size: 72, weight: .light, design: .serif))
                    .foregroundStyle(AthanTheme.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(allPassed ? "UNTIL FAJR" : "REMAINING")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(AthanTheme.textSecondary)
                    .tracking(1)
                    .padding(.leading, 4)
            }
            .padding(.bottom, 20)

            // Progress bar
            PrayerProgressBar(progress: progress)
                .padding(.bottom, 20)

            // Bottom: adhan time + done button
            HStack {
                (Text(allPassed ? "Fajr at " : "Adhan at ")
                    .foregroundStyle(AthanTheme.textSecondary)
                 + Text(timeString)
                    .foregroundStyle(AthanTheme.textPrimary.opacity(0.7)))
                .font(.system(size: 15))

                Spacer()

                if !allPassed {
                    Button(action: onDone) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                            Text("DONE")
                                .font(.system(size: 13, weight: .medium))
                                .tracking(1)
                        }
                        .foregroundStyle(AthanTheme.accent.opacity(0.85))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(AthanTheme.accent.opacity(0.1))
                                .overlay(Capsule().stroke(AthanTheme.accent.opacity(0.12), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.success, trigger: isCompleted)
                }
            }
        }
        .padding(28)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(AthanTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(AthanTheme.cardBorder, lineWidth: 1)
                )
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [.clear, AthanTheme.cardEdgeHighlight, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 1)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next prayer: \(prayer.displayName), \(countdown ?? "unknown") remaining, adhan at \(timeString)")
    }
}

// MARK: - Sun Icon (glowing orb + horizon)

private struct SunIconView: View {
    var body: some View {
        ZStack {
            // Outer glow halo
            Circle()
                .fill(AthanTheme.accent.opacity(0.08))
                .frame(width: 32, height: 32)
                .offset(y: -3)

            // Main orb with 3D gradient (bright top-left highlight → deep bottom-right)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AthanTheme.accent.opacity(1.0),
                            AthanTheme.accent.opacity(0.8),
                            AthanTheme.accentDeep.opacity(0.5)
                        ],
                        center: UnitPoint(x: 0.35, y: 0.35),
                        startRadius: 0,
                        endRadius: 12
                    )
                )
                .frame(width: 22, height: 22)
                .overlay {
                    // Specular highlight for 3D depth
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.5), .clear],
                                center: UnitPoint(x: 0.3, y: 0.3),
                                startRadius: 0,
                                endRadius: 6
                            )
                        )
                        .frame(width: 22, height: 22)
                }
                .shadow(color: AthanTheme.accent.opacity(0.5), radius: 10, y: 2)
                .offset(y: -3)

            // Horizon line
            LinearGradient(
                colors: [.clear, AthanTheme.accent.opacity(0.5), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 38, height: 1)
            .offset(y: 10)
        }
    }
}

// MARK: - Progress Bar

private struct PrayerProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.06))

                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [AthanTheme.accent.opacity(0.6), AthanTheme.accentDeep.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * CGFloat(progress)))
                    .animation(.easeOut(duration: 0.8), value: progress)
            }
        }
        .frame(height: 2)
    }
}

// MARK: - Geometric Accent Overlay

private struct GeometricAccentView: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width - 20, y: 120)
            let white = Color.white

            // Concentric circles
            for (radius, lineWidth) in [(80.0, 0.5), (60.0, 0.3), (40.0, 0.3)] as [(CGFloat, CGFloat)] {
                let rect = CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                )
                context.stroke(Circle().path(in: rect), with: .color(white), lineWidth: lineWidth)
            }

            // Diamond shapes (rotated squares)
            for radius: CGFloat in [80, 60] {
                var path = Path()
                path.move(to: CGPoint(x: center.x, y: center.y - radius))
                path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
                path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
                path.closeSubpath()
                context.stroke(path, with: .color(white), lineWidth: 0.3)
            }
        }
    }
}
