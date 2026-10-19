import SwiftUI
import HealthKit
import UIKit

/// A comprehensive first-install walkthrough and onboarding flow.
///
/// `OnboardingView` introduces Runalyst's core value propositions, highlights the ⓘ metric explainer system,
/// prompts for Apple Health connectivity, and immediately initiates background workout sync and baseline
/// calibration while the runner reads through the app philosophy and "About Runalyst" guide.
struct OnboardingView: View {
    var isReplay: Bool = false
    var isSyncing: Bool = false
    var syncProgress: (current: Int, total: Int)?
    var syncStatusMessage: String?
    var onStartSync: (() -> Void)?
    var onComplete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @AppStorage("trainingGoal") private var trainingGoal: String = "Base Building"
    @AppStorage("userExperienceLevel") private var userExperienceLevel: String = "Auto"
    @AppStorage("userHeightCm") private var userHeightCm: Double = 175.0
    @StateObject private var healthKitManager = HealthKitManager.shared

    private let goalOptions = [
        "Base Building",
        "Injury Recovery",
        "5K Race",
        "10K Race",
        "Half Marathon",
        "Marathon",
        "Just for Fun"
    ]

    @State private var currentPage: Int = 0
    @State private var isRequestingAuth: Bool = false
    @State private var authErrorMessage: String?
    @State private var isHealthAuthorized: Bool = false
    @State private var previewExplainer: MetricExplainerInfo?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    headerBar

                    TabView(selection: $currentPage) {
                        welcomeStepView
                            .tag(0)

                        healthConnectionStepView
                            .tag(1)

                        profileSetupStepView
                            .tag(2)

                        aboutRunalystStepView
                            .tag(3)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.3), value: currentPage)

                    bottomControls
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $previewExplainer) { info in
                MetricExplainerSheet(info: info)
            }
            .task {
                checkInitialAuthStatus()
                if let healthHeight = try? await HealthKitManager.shared.fetchUserHeight(), healthHeight > 0 {
                    if UserDefaults.standard.object(forKey: "userHeightCm") == nil || userHeightCm == 175.0 {
                        userHeightCm = healthHeight
                    }
                }
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            if currentPage > 0 {
                Button {
                    withAnimation {
                        currentPage -= 1
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            } else {
                Spacer().frame(width: 50)
            }

            Spacer()

            // Page Indicator Dots (4 Pages)
            HStack(spacing: 6) {
                ForEach(0..<4) { index in
                    Capsule()
                        .fill(currentPage == index ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: currentPage == index ? 20 : 6, height: 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                }
            }

            Spacer()

            if currentPage < 3 {
                if isReplay {
                    Button("Close") {
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                } else {
                    Button("Skip") {
                        withAnimation {
                            currentPage = 3
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            } else {
                Button("Done") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if isReplay {
                        dismiss()
                    } else {
                        onComplete?()
                    }
                }
                .font(.subheadline.bold())
                .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Step 0: Welcome & Features + ⓘ Explainer Spotlight

    private var welcomeStepView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.teal, Color.blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                            .shadow(color: Color.teal.opacity(0.35), radius: 12, x: 0, y: 6)

                        Image(systemName: "figure.run")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 8)

                    Text("Meet Your AI\nRunning Coach")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("Precision biomechanical analysis, form-targeted drills, and 100% on-device private coaching.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                // Core Pillars
                VStack(spacing: 14) {
                    walkthroughFeatureCard(
                        icon: "arrow.triangle.2.circlepath",
                        iconColor: .teal,
                        title: "Passive HealthKit Sync",
                        description: "No manual clocks or phone carrying. Runalyst automatically ingests and analyzes workouts logged on your Apple Watch."
                    )

                    walkthroughFeatureCard(
                        icon: "lock.shield.fill",
                        iconColor: .green,
                        title: "100% Private On-Device AI",
                        description: "Apple Foundation Models coach your running form locally on your iPhone. Your workout metrics never leave your device."
                    )

                    walkthroughFeatureCard(
                        icon: "chart.xyaxis.line",
                        iconColor: .purple,
                        title: "Adaptive Rolling Baselines",
                        description: "Every metric is measured against your personal 30-day baseline — never against arbitrary, one-size-fits-all averages."
                    )
                }
                .padding(.horizontal, 16)

                // Spotlight on the ⓘ Explainer
                infoExplainerSpotlightCard
                    .padding(.horizontal, 16)

                Spacer().frame(height: 40)
            }
            .padding(.vertical, 12)
            .padding(.bottom, 90)
        }
    }

    private var infoExplainerSpotlightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.title3)
                    .foregroundColor(.blue)

                Text("Tap ⓘ Anywhere for Deep Dives")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Text("Try It")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }

            Text("Notice the ⓘ icons across the dashboard and workout views? Tap any ⓘ icon anytime for plain-English definitions, calculation methodology, and biomechanical coaching context.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineSpacing(2)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                previewExplainer = MetricExplainerInfo(
                    explainer: MetricDetailExplainer.explainer(for: "Average Cadence", isWorkoutStats: false)
                )
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundColor(.teal)
                        .font(.body)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Interactive Preview: Working Cadence")
                            .font(.caption.bold())
                            .foregroundColor(.primary)
                        Text("Tap to see a sample metric explanation")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                        .font(.headline)
                }
                .padding(12)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .cornerRadius(12)
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Step 1: Connect Apple Health

    private var healthConnectionStepView: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.pink, Color.red.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                            .shadow(color: Color.red.opacity(0.35), radius: 12, x: 0, y: 6)

                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 8)

                    Text("Connect Apple Health")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("Runalyst reads your historical runs to calibrate your baseline and personalize your AI coaching drills.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                VStack(spacing: 14) {
                    walkthroughFeatureCard(
                        icon: "figure.run",
                        iconColor: .orange,
                        title: "Running Workouts",
                        description: "Distance, duration, active pace, and elevation profiles."
                    )

                    walkthroughFeatureCard(
                        icon: "waveform.path.ecg",
                        iconColor: .teal,
                        title: "Cadence & Form Biometrics",
                        description: "Step rate (SPM), vertical bounce (oscillation), and ground contact time."
                    )

                    walkthroughFeatureCard(
                        icon: "heart.fill",
                        iconColor: .red,
                        title: "Heart Rate & VO2 Max",
                        description: "Aerobic stability, cardiovascular strain, and endurance tracking."
                    )
                }
                .padding(.horizontal, 16)

                // Health Connect Button / State
                VStack(spacing: 12) {
                    if isHealthAuthorized {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title3)

                            Text("Apple Health Connected")
                                .font(.headline)
                                .foregroundColor(.primary)

                            Spacer()

                            Image(systemName: "bolt.horizontal.fill")
                                .foregroundColor(.teal)
                                .font(.caption)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                    } else {
                        Button(action: {
                            requestHealthAccess()
                        }) {
                            HStack(spacing: 10) {
                                if isRequestingAuth {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "heart.text.square")
                                        .font(.headline)
                                    Text("Connect Apple Health")
                                        .font(.headline)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .disabled(isRequestingAuth)
                    }

                    if let error = authErrorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal)
                    }

                    // Background sync status indicator if sync has begun
                    if isSyncing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(syncStatusMessage ?? "Syncing running workouts in the background...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)

                Spacer().frame(height: 40)
            }
            .padding(.vertical, 12)
            .padding(.bottom, 90)
        }
    }

    // MARK: - Step 2: Athlete Profile Setup

    private var profileSetupStepView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.teal, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                            .shadow(color: Color.teal.opacity(0.35), radius: 12, x: 0, y: 6)

                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 38))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 8)

                    Text("Your Runner Profile")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("Tune your primary training intent and biomechanics so AI coaching directives and cadence floors match your biology.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                // Profile Configuration Cards
                VStack(spacing: 16) {
                    // Card 1: Primary Training Goal
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "target")
                                .font(.headline)
                                .foregroundColor(.teal)
                            Text("Primary Training Goal")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }

                        Picker("Training Goal", selection: $trainingGoal) {
                            ForEach(goalOptions, id: \.self) { goal in
                                Text(goal).tag(goal)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.teal)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Text(goalDescription(for: trainingGoal))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Card 2: Experience Level
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.headline)
                                .foregroundColor(.purple)
                            Text("Experience Level")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }

                        Picker("Experience Level", selection: $userExperienceLevel) {
                            Text("Auto (Calibrated from Health)").tag("Auto")
                            ForEach(RunnerProfile.experienceLevelOptions, id: \.self) { level in
                                Text(level).tag(level)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.purple)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Text(userExperienceLevel == "Auto"
                            ? "Auto dynamically classifies your athletic maturity tier from 30-day running volume and frequency."
                            : "Manual override active: \(userExperienceLevel). Runalyst will tailor interval pacing to this level.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Card 3: Biomechanical Height
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "ruler.fill")
                                .font(.headline)
                                .foregroundColor(.orange)
                            Text("Biomechanical Height")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            if useMetricSystem {
                                Text("\(Int(userHeightCm)) cm")
                                    .font(.headline.bold())
                                    .monospacedDigit()
                                    .foregroundColor(.orange)
                            } else {
                                let totalInches = Int((userHeightCm / 2.54).rounded())
                                let feet = totalInches / 12
                                let inches = totalInches % 12
                                Text("\(feet)'\(inches)\" (\(Int(userHeightCm)) cm)")
                                    .font(.headline.bold())
                                    .monospacedDigit()
                                    .foregroundColor(.orange)
                            }
                        }

                        Stepper(
                            value: $userHeightCm,
                            in: 130...220,
                            step: 1
                        ) {
                            Text("Adjust Height")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Text("Used by the physics engine to calculate your height-adjusted cadence floor and vertical oscillation limit.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 16)

                Spacer().frame(height: 40)
            }
            .padding(.vertical, 12)
            .padding(.bottom, 90)
        }
    }

    private func goalDescription(for goal: String) -> String {
        switch goal {
        case "Base Building":
            return "Prioritizes easy aerobic base mileage and conversational heart rate caps."
        case "Injury Recovery":
            return "Conservative volume caps with proactive recovery directives overriding hard workouts."
        case "5K Race":
            return "Develops rapid turnover, cadence stability, and sharp neuromuscular surge speed."
        case "10K Race":
            return "Balances sustained threshold endurance with structured aerobic rhythm intervals."
        case "Half Marathon":
            return "Builds progressive aerobic stamina and stride efficiency over sustained distances."
        case "Marathon":
            return "Focuses on deep aerobic adaptation, cadence stability, and fatigue resistance."
        default:
            return "Balanced aerobic coaching for consistent fitness and injury-free running."
        }
    }

    // MARK: - Step 3: About Runalyst & Live Background Sync

    private var aboutRunalystStepView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Live background sync calibration banner
                backgroundSyncStatusBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                // Embedded About Runalyst content from Settings
                AboutRunalystView(isEmbedded: true)
                    .padding(.horizontal, 16)

                Spacer().frame(height: 40)
            }
            .padding(.bottom, 90)
        }
    }

    @ViewBuilder
    private var backgroundSyncStatusBanner: some View {
        if isSyncing {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .symbolEffect(.bounce.up, options: .repeating)

                    Text(syncStatusMessage ?? "Calibrating History...")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)

                    Spacer()

                    if let progress = syncProgress, progress.total > 0 {
                        Text("\(progress.current)/\(progress.total)")
                            .font(.caption.bold())
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }

                if let progress = syncProgress, progress.total > 0 {
                    ProgressView(value: Double(progress.current), total: Double(progress.total))
                        .tint(.accentColor)
                } else {
                    ProgressView()
                        .tint(.accentColor)
                }

                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                    Text("Syncing & calibrating in the background. Take your time reading through our philosophy!")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        } else if isHealthAuthorized {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Calibration Complete")
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                    Text("Your personal 30-day running baselines are ready.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.green.opacity(0.25), lineWidth: 1)
            )
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 12) {
            Divider()

            HStack {
                if currentPage == 0 {
                    Button {
                        withAnimation {
                            currentPage = 1
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack {
                            Text("Get Started")
                                .font(.headline)
                            Image(systemName: "arrow.right")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                } else if currentPage == 1 {
                    Button {
                        withAnimation {
                            currentPage = 2
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack {
                            Text(isHealthAuthorized ? "Next: Runner Profile" : "Continue to Runner Profile")
                                .font(.headline)
                            Image(systemName: "arrow.right")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isHealthAuthorized ? Color.accentColor : Color.primary)
                        .foregroundColor(Color(UIColor.systemBackground))
                        .cornerRadius(16)
                    }
                } else if currentPage == 2 {
                    Button {
                        withAnimation {
                            currentPage = 3
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack {
                            Text("Next: App Philosophy")
                                .font(.headline)
                            Image(systemName: "arrow.right")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if isReplay {
                            dismiss()
                        } else {
                            onComplete?()
                        }
                    } label: {
                        HStack {
                            Text(isReplay ? "Done" : "Start Running with Runalyst")
                                .font(.headline)
                            Image(systemName: isReplay ? "checkmark" : "figure.run")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(.regularMaterial)
    }

    // MARK: - Helpers

    private func walkthroughFeatureCard(
        icon: String,
        iconColor: Color,
        title: String,
        description: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 32, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func requestHealthAccess() {
        isRequestingAuth = true
        authErrorMessage = nil

        Task {
            do {
                try await healthKitManager.requestAuthorization()
                await MainActor.run {
                    self.isHealthAuthorized = true
                    self.isRequestingAuth = false
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                // Initiate background sync immediately
                onStartSync?()

                // Transition smoothly to Step 2
                try? await Task.sleep(nanoseconds: 600_000_000)
                await MainActor.run {
                    withAnimation {
                        self.currentPage = 2
                    }
                }
            } catch {
                await MainActor.run {
                    self.authErrorMessage = "Health access error: \(error.localizedDescription)"
                    self.isRequestingAuth = false
                }
            }
        }
    }

    private func checkInitialAuthStatus() {
        guard healthKitManager.isHealthDataAvailable() else { return }
        let status = healthKitManager.healthStore?.authorizationStatus(for: HKObjectType.workoutType())
        if status == .sharingAuthorized {
            isHealthAuthorized = true
        }
    }
}

#Preview {
    OnboardingView()
}
