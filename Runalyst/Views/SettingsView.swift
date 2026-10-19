import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric

    @Query private var runRecords: [RunRecord]

    var onForceSync: ((Bool) async -> Void)?

    @State private var showWalkthroughSheet = false

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
            PermissionsSyncSectionView(runRecords: runRecords, onForceSync: onForceSync)

            // MARK: - Data Management & Smart Coach
            DataManagementSectionView(runRecords: runRecords, onForceSync: onForceSync)

            // MARK: - About
            Section(header: Text("About")) {
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
    }
}
