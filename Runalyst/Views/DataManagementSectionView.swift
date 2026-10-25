import SwiftUI
import SwiftData

struct DataManagementSectionView: View {
    @Environment(\.modelContext) private var modelContext
    let runRecords: [RunRecord]
    var onForceSync: ((Bool) async -> Void)?

    @State private var showSyncAlert = false
    @State private var showResetModelAlert = false
    @State private var isSeeding = false
    @State private var seedingSuccess = false

    var body: some View {
        Group {
            // MARK: - Troubleshooting & Diagnostics
            Section(
                header: Text("Troubleshooting & Diagnostics"),
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
                        DailyTrainingStateStore.shared.invalidate()
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

            // MARK: - Smart Coach Diagnostics (CoreML & AI)
            Section(
                header: Text("Smart Coach Diagnostics (CoreML & AI)"),
                footer: Text("Resets on-device runner classification corrections back to baseline without affecting your recorded workouts or training goal.")
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
        }
    }
}
