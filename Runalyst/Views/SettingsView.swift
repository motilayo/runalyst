import SwiftUI
import SwiftData
import HealthKit
@preconcurrency import WorkoutKit

struct SettingsView: View {
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric

    @Environment(\.modelContext) private var modelContext
    @Query private var runRecords: [RunRecord]

    var onForceSync: ((Bool) async -> Void)?

    @State private var showSyncAlert = false
    @State private var showResetModelAlert = false
    @State private var showWalkthroughSheet = false
    @State private var isSeeding = false
    @State private var seedingSuccess = false

    @State private var healthAuthStatus: String = "Checking..."
    @State private var workoutKitAuthStatus: String = "Checking..."
    @State private var canRequestHealth: Bool = false
    @State private var canRequestWorkoutKit: Bool = false
    @State private var showHealthSettingsAlert = false
    @State private var showWorkoutKitSettingsAlert = false

    var body: some View {
        Form {
            // MARK: - Account
            Section(header: Text("Account")) {
                NavigationLink(destination: UserProfileView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundColor(.teal)
                            .font(.title3)
                        Text("User Profile")
                            .font(.body)
                    }
                }
            }

            // MARK: - Preferences
            Section(header: Text("Preferences")) {
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: "ruler")
                            .foregroundColor(.teal)
                            .font(.title3)
                        Text("Unit System")
                            .font(.body)
                    }

                    Spacer()

                    Picker("Unit System", selection: $useMetricSystem) {
                        Text("Metric").tag(true)
                        Text("Imperial").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                }
            }

            // MARK: - Permissions & Sync
            Section(
                header: Text("Permissions & Sync"),
                footer: Text("Tap a permission to request access directly in the app.")
            ) {
                Button(action: {
                    Task {
                        let prevStatus = try? await HealthKitManager.shared.getRequestStatusForAuthorization()
                        do {
                            try await HealthKitManager.shared.requestAuthorization()
                            await updateHealthKitStatus()
                            if let onForceSync = onForceSync {
                                await onForceSync(false)
                            }
                        } catch {
                            print("Health authorization error: \(error.localizedDescription)")
                        }

                        if prevStatus == .unnecessary {
                            showHealthSettingsAlert = true
                        }
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .font(.title3)
                        Text("Apple Health Data")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(healthAuthStatus)
                            .font(.subheadline.bold())
                            .foregroundColor(healthAuthStatus == "Connected" ? Color(red: 0.1, green: 0.6, blue: 0.6) : (healthAuthStatus == "Not Connected" ? .orange : .secondary))
                    }
                }
                .alert("Apple Health Permissions", isPresented: $showHealthSettingsAlert) {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You have already been prompted for Apple Health permissions. If you are missing data, please go to the iOS Settings app to review your Runalyst Health permissions.")
                }

                Button(action: {
                    Task {
                        if #available(iOS 17.0, *) {
                            let prevState = await WorkoutScheduler.shared.authorizationState
                            _ = await WorkoutScheduler.shared.requestAuthorization()
                            await updateWorkoutKitStatus()
                            if prevState != .notDetermined {
                                showWorkoutKitSettingsAlert = true
                            }
                        } else {
                            showWorkoutKitSettingsAlert = true
                        }
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "applewatch")
                            .foregroundColor(.primary)
                            .font(.title3)
                        Text("WorkoutKit Handoff")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(workoutKitAuthStatus)
                            .font(.subheadline.bold())
                            .foregroundColor(workoutKitAuthStatus == "Granted" ? Color(red: 0.1, green: 0.6, blue: 0.6) : (workoutKitAuthStatus == "Denied" ? .red : .secondary))
                    }
                }
                .alert("WorkoutKit Handoff", isPresented: $showWorkoutKitSettingsAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("WorkoutKit permission is already \(workoutKitAuthStatus.lowercased()) on this device.")
                }
            }

            // MARK: - Data Management
            Section(
                header: Text("Data Management"),
                footer: Text("Re-fetches recent workouts from Apple Health, wipes local records and cache, and regenerates fresh AI insights.")
            ) {
                Button(action: { showSyncAlert = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.teal)
                            .font(.title3)
                        Text("Resync Health Data & Rebuild AI Insights")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
                .alert("Resync & Rebuild Insights", isPresented: $showSyncAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Resync & Rebuild", role: .destructive) {
                        for run in runRecords {
                            modelContext.delete(run)
                        }
                        try? modelContext.save()
                        WorkoutBridge.clearIntents()
                        UserDefaults.standard.removeObject(forKey: "cachedHeadline_7Day")
                        UserDefaults.standard.removeObject(forKey: "cachedBody_7Day")
                        UserDefaults.standard.removeObject(forKey: "cachedHeadline_30Day")
                        UserDefaults.standard.removeObject(forKey: "cachedBody_30Day")
                        UserDefaults.standard.removeObject(forKey: "cachedHeadline_AllTime")
                        UserDefaults.standard.removeObject(forKey: "cachedBody_AllTime")
                        if let onForceSync = onForceSync {
                            Task { await onForceSync(true) }
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                } message: {
                    Text("This will delete all locally saved run records, clear cached AI insights, and re-fetch them from Apple Health. This cannot be undone.")
                }

                #if DEBUG
                Button(action: {
                    isSeeding = true
                    Task {
                        await HealthKitSeeder.shared.seedCouchTo5K(context: modelContext)
                        if let onForceSync = onForceSync {
                            await onForceSync(false)
                        }
                        await MainActor.run {
                            isSeeding = false
                            seedingSuccess = true
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "ladybug.fill")
                            .foregroundColor(.orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Seed Sample Health Data (Debug)")
                                .foregroundColor(.primary)
                            Text("Seeds 3 months of runs (38 runs) with beginner progression & aligned drills")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if isSeeding {
                            ProgressView()
                        } else if seedingSuccess {
                            Image(systemName: "checkmark")
                                .foregroundColor(.green)
                        }
                    }
                }
                .disabled(isSeeding)
                #endif
            }

            // MARK: - Smart Coach (CoreML & AI)
            Section(
                header: Text("Smart Coach (CoreML & AI)"),
                footer: Text("Resetting the model deletes your local training queue and resets to baseline.")
            ) {
                Button(action: { showResetModelAlert = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.pink)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reset Personalization Model")
                                .foregroundColor(.primary)
                            Text("(Deletes local training queue and resets to baseline)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                .alert("Reset Personalization Model", isPresented: $showResetModelAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        let descriptor = FetchDescriptor<TrainingCorrection>()
                        if let corrections = try? modelContext.fetch(descriptor) {
                            for item in corrections {
                                modelContext.delete(item)
                            }
                            try? modelContext.save()
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                } message: {
                    Text("This resets the on-device runner classification queue back to baseline.")
                }
            }

            // MARK: - About
            Section {
                Button {
                    showWalkthroughSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.run.circle")
                            .foregroundColor(.teal)
                            .font(.title3)
                        Text("App Walkthrough")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                NavigationLink(destination: AboutRunalystView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                        Text("About Runalyst")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showWalkthroughSheet) {
            OnboardingView(isReplay: true, onComplete: {
                showWalkthroughSheet = false
            })
        }
        .task {
            await refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await refreshPermissions()
            }
        }
    }

    private func refreshPermissions() async {
        await updateHealthKitStatus()
        await updateWorkoutKitStatus()
    }

    private func updateHealthKitStatus() async {
        guard HealthKitManager.shared.isHealthDataAvailable() else {
            await MainActor.run {
                self.healthAuthStatus = "Unavailable"
                self.canRequestHealth = false
            }
            return
        }

        do {
            let status = try await HealthKitManager.shared.getRequestStatusForAuthorization()
            await MainActor.run {
                switch status {
                case .shouldRequest:
                    self.healthAuthStatus = "Not Connected"
                    self.canRequestHealth = true
                case .unnecessary:
                    self.healthAuthStatus = runRecords.isEmpty ? "Manage" : "Connected"
                    self.canRequestHealth = false
                case .unknown:
                    self.healthAuthStatus = "Manage"
                    self.canRequestHealth = false
                @unknown default:
                    self.healthAuthStatus = "Manage"
                    self.canRequestHealth = false
                }
            }
        } catch {
            await MainActor.run {
                self.healthAuthStatus = runRecords.isEmpty ? "Manage" : "Connected"
                self.canRequestHealth = false
            }
        }
    }

    private func updateWorkoutKitStatus() async {
        if #available(iOS 17.0, *) {
            let state = await WorkoutScheduler.shared.authorizationState
            await MainActor.run {
                switch state {
                case .authorized:
                    self.workoutKitAuthStatus = "Granted"
                    self.canRequestWorkoutKit = false
                case .denied, .restricted:
                    self.workoutKitAuthStatus = "Denied"
                    self.canRequestWorkoutKit = false
                case .notDetermined:
                    self.workoutKitAuthStatus = "Not Determined"
                    self.canRequestWorkoutKit = true
                @unknown default:
                    self.workoutKitAuthStatus = "Manage"
                    self.canRequestWorkoutKit = false
                }
            }
        } else {
            await MainActor.run {
                self.workoutKitAuthStatus = "Unavailable"
                self.canRequestWorkoutKit = false
            }
        }
    }
}
