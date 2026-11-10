import RunalystCore
import SwiftUI

// MARK: - Start Run View

/// Hollow configuration view for starting a watch workout session.
///
/// Binds exclusively to `WatchTargetPaceOption` presets and displays the target pace picker
/// only when today's prescription requires manual selection. Zero inline math.
public struct StartRunView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(PacingViewModel.self) private var pacingViewModel

    @State private var selectedLocation: PacingLocation = WatchContextStore.shared.preferredLocation
    @State private var hasUserManuallySelectedLocation = false
    @State private var selectedPaceOption: WatchTargetPaceOption = .justRun
    @State private var isNavigatingToGauge = false

    public init() {}

    private var resolvedConfig: WatchResolvedSessionConfig {
        WatchContextStore.shared.resolveSession(selectedPace: selectedPaceOption.paceSecondsPerKm)
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    // Prescribed Drill Hero Card (if published from iPhone)
                    if resolvedConfig.hasPrescribedDrill, let title = resolvedConfig.prescribedDrillTitle {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "figure.run")
                                    .foregroundStyle(.green)
                                Text("PRESCRIBED DRILL")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }

                            Text(title)
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(.white)

                            HStack(spacing: 8) {
                                if let cadence = resolvedConfig.targetCadenceFormatted {
                                    Text(cadence)
                                        .font(.system(.caption2, design: .rounded))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.green)
                                }
                                if let duration = resolvedConfig.durationFormatted {
                                    Text(duration)
                                        .font(.system(.caption2, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(12)
                    }

                    // Location Picker
                    Picker("Environment", selection: Binding(
                        get: { selectedLocation },
                        set: { newLocation in
                            selectedLocation = newLocation
                            hasUserManuallySelectedLocation = true
                        }
                    )) {
                        Text("Outdoor").tag(PacingLocation.outdoor)
                        Text("Indoor").tag(PacingLocation.indoor)
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 50)

                    // Target Pace Picker (shown only when required)
                    if resolvedConfig.requiresTargetPacePicker {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Target Pace")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)

                            Picker("Target Pace", selection: $selectedPaceOption) {
                                ForEach(WatchTargetPaceOption.allOptions) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 60)
                        }
                    }

                    // Start Button (minimum 44x44pt hit target)
                    Button {
                        Task {
                            await workoutManager.startWorkout(
                                location: selectedLocation,
                                targetPaceSecondsPerKm: selectedPaceOption.paceSecondsPerKm,
                                viewModel: pacingViewModel
                            )
                            isNavigatingToGauge = true
                        }
                    } label: {
                        Text(resolvedConfig.hasPrescribedDrill ? "Start Drill" : "Start Run")
                            .font(.system(.headline, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.green)
                            .foregroundColor(.black)
                            .cornerRadius(22)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal)
            }
        }
        .onAppear {
            if !hasUserManuallySelectedLocation {
                selectedLocation = WatchContextStore.shared.preferredLocation
            }
        }
        .onChange(of: WatchContextStore.shared.preferredLocation) { _, newLocation in
            if !hasUserManuallySelectedLocation {
                selectedLocation = newLocation
            }
        }
        .task {
            if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == nil {
                _ = await workoutManager.requestAuthorization()
            }
        }
        .navigationDestination(isPresented: $isNavigatingToGauge) {
            PacingGaugeView()
        }
    }
}
