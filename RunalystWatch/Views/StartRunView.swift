import RunalystCore
import SwiftUI

// MARK: - Start Run View

/// Hollow configuration view for starting a watch workout session.
///
/// Binds exclusively to `WatchRunIntent` and `WatchResolvedSessionConfig`.
/// Zero inline domain math.
public struct StartRunView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(PacingViewModel.self) private var pacingViewModel

    @State private var selectedLocation: PacingLocation = WatchContextStore.shared.preferredLocation
    @State private var hasUserManuallySelectedLocation = false
    @State private var selectedIntent: WatchRunIntent = .adaptiveBase
    @State private var selectedPaceOption: WatchTargetPaceOption = .justRun

    public init() {}

    private var resolvedConfig: WatchResolvedSessionConfig {
        WatchContextStore.shared.resolveSession(
            runIntent: selectedIntent,
            selectedPace: selectedPaceOption.paceSecondsPerKm
        )
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
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // High-contrast Outdoor / Indoor Selector (44pt+ height)
                    HStack(spacing: 8) {
                        locationButton(
                            title: "Outdoor",
                            icon: "sun.max.fill",
                            location: .outdoor
                        )

                        locationButton(
                            title: "Indoor",
                            icon: "figure.run.square.stack.fill",
                            location: .indoor
                        )
                    }

                    // 3-Option Run Intent Picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RUN INTENT")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 2)

                        VStack(spacing: 6) {
                            ForEach(WatchRunIntent.allCases) { intent in
                                intentRow(intent)
                            }
                        }
                    }

                    // Target Pace Picker (shown only when required by prescription)
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
                            let targetPace = resolvedConfig.requiresTargetPacePicker ? selectedPaceOption.paceSecondsPerKm : nil
                            await workoutManager.startWorkout(
                                location: selectedLocation,
                                intent: selectedIntent,
                                targetPaceSecondsPerKm: targetPace,
                                viewModel: pacingViewModel
                            )
                            workoutManager.isNavigatingToGauge = true
                        }
                    } label: {
                        Text(resolvedConfig.hasPrescribedDrill ? "Start Drill" : "Start Run")
                            .font(.system(.headline, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.green)
                            .foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal)
            }
        }
        .onAppear {
            if workoutManager.sessionState == .running || workoutManager.sessionState == .paused {
                workoutManager.isNavigatingToGauge = true
            }
            if !hasUserManuallySelectedLocation {
                selectedLocation = WatchContextStore.shared.preferredLocation
            }
            WatchContextStore.shared.requestLatestContextIfNeeded()
        }
        .onChange(of: WatchContextStore.shared.preferredLocation) { _, newLocation in
            if !hasUserManuallySelectedLocation {
                selectedLocation = newLocation
            }
        }
        .task {
            if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == nil {
                _ = await workoutManager.requestAuthorizationIfNeeded()
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { workoutManager.isNavigatingToGauge },
            set: { workoutManager.isNavigatingToGauge = $0 }
        )) {
            PacingGaugeView()
        }
    }

    private func locationButton(title: String, icon: String, location: PacingLocation) -> some View {
        Button {
            selectedLocation = location
            hasUserManuallySelectedLocation = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selectedLocation == location ? Color.blue.opacity(0.35) : Color.white.opacity(0.1))
            .foregroundStyle(selectedLocation == location ? .white : .secondary)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedLocation == location ? Color.cyan : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func intentRow(_ intent: WatchRunIntent) -> some View {
        Button {
            selectedIntent = intent
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(intent.title)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Text(intent.subtitle)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedIntent == intent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.body)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selectedIntent == intent ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedIntent == intent ? Color.green : Color.white.opacity(0.1), lineWidth: selectedIntent == intent ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
