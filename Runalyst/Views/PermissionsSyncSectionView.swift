import SwiftUI
import HealthKit
#if canImport(WorkoutKit)
@preconcurrency import WorkoutKit
#endif

struct PermissionsSyncSectionView: View {
    let runRecords: [RunRecord]
    var onForceSync: ((Bool) async -> Void)?

    @State private var healthAuthStatus: String = "Checking..."
    @State private var workoutKitAuthStatus: String = "Checking..."
    @State private var canRequestHealth: Bool = false
    @State private var canRequestWorkoutKit: Bool = false
    @State private var showHealthSettingsAlert = false
    @State private var showWorkoutKitSettingsAlert = false

    var body: some View {
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
                if workoutKitAuthStatus == "Denied" {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: {
                if workoutKitAuthStatus == "Denied" {
                    Text("WorkoutKit permission is currently denied. To enable sending drills directly to your Apple Watch, please enable WorkoutKit in your iOS Settings.")
                } else {
                    Text("WorkoutKit permission is already \(workoutKitAuthStatus.lowercased()) on this device.")
                }
            }
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
