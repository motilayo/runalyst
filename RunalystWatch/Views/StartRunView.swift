import RunalystCore
import SwiftUI

// MARK: - Start Run View

/// Hollow configuration view for starting a watch workout session.
/// Binds exclusively to `WatchRunIntent` and `WatchResolvedSessionConfig`. Zero inline domain math.
public struct StartRunView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(PacingViewModel.self) private var pacingViewModel

    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric

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

    private var heroAccentColor: Color {
        resolvedConfig.hasPrescribedDrill ? WatchColor.cadence : WatchColor.companionAccent
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 8) {
                    heroCard
                    startWorkoutCTA
                    locationSelector
                    if !resolvedConfig.hasPrescribedDrill {
                        runIntentSelector
                    }

                    if resolvedConfig.requiresTargetPacePicker {
                        targetPacePicker
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 12)
            }
        }
        .onAppear {
            if workoutManager.sessionState == .running || workoutManager.sessionState == .paused {
                workoutManager.isNavigatingToGauge = true
            }
            if !hasUserManuallySelectedLocation { selectedLocation = WatchContextStore.shared.preferredLocation }
            if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == nil {
                WatchContextStore.shared.requestLatestContextIfNeeded()
            }
        }
        .onChange(of: WatchContextStore.shared.preferredLocation) { _, newLoc in
            if !hasUserManuallySelectedLocation { selectedLocation = newLoc }
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

    // MARK: - Subviews

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(heroAccentColor.opacity(0.15)).frame(width: 20, height: 20)
                    Image(systemName: resolvedConfig.hasPrescribedDrill ? WatchIcon.drill : WatchIcon.companion)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(heroAccentColor)
                }

                Text(resolvedConfig.sessionHeaderBadgeText)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(heroAccentColor)

                Spacer()

                if let duration = resolvedConfig.durationFormatted {
                    Text(duration.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(resolvedConfig.sessionTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(resolvedConfig.sessionSubtitle)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 0) {
                heroStatColumn(icon: WatchIcon.pace, label: "PACE", value: resolvedConfig.targetPaceFormatted(useMetric: useMetricSystem), iconColor: WatchColor.pace)
                Divider().frame(height: 18).opacity(0.25)
                heroStatColumn(icon: WatchIcon.cadence, label: "CADENCE", value: resolvedConfig.targetCadencePillText, iconColor: WatchColor.cadence)
                Divider().frame(height: 18).opacity(0.25)
                heroStatColumn(icon: WatchIcon.heartRate, label: "MAX HR", value: resolvedConfig.aerobicCeilingPillText, iconColor: WatchColor.heartRate)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            .padding(.top, 2)
        }
        .padding(10)
        .watchLiquidGlass(accent: heroAccentColor, cornerRadius: 14, isProminent: true)
    }

    private func heroStatColumn(icon: String, label: String, value: String, iconColor: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 7, weight: .bold)).foregroundStyle(iconColor)
                Text(label).font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }

    private var startWorkoutCTA: some View {
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
            HStack(spacing: 6) {
                Image(systemName: "play.fill").font(.system(.subheadline, design: .rounded).bold())
                Text(resolvedConfig.primaryCtaTitle).font(.system(.headline, design: .rounded)).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(.black)
            .background(WatchColor.cadence)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private var locationSelector: some View {
        HStack(spacing: 6) {
            locationButton(title: "Outdoor", icon: WatchIcon.outdoor, location: .outdoor)
            locationButton(title: "Indoor", icon: WatchIcon.indoor, location: .indoor)
        }
    }

    private func locationButton(title: String, icon: String, location: PacingLocation) -> some View {
        let isSelected = selectedLocation == location
        return Button {
            selectedLocation = location
            hasUserManuallySelectedLocation = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2).foregroundStyle(isSelected ? WatchColor.pace : .secondary)
                Text(title).font(.system(.subheadline, design: .rounded)).fontWeight(.semibold).foregroundStyle(isSelected ? .white : .secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .neutralWatchSurface(isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    private var runIntentSelector: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("RUN INTENT")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            VStack(spacing: 5) {
                ForEach(WatchRunIntent.allCases) { intent in
                    intentRow(intent)
                }
            }
        }
    }

    private func intentRow(_ intent: WatchRunIntent) -> some View {
        let isSelected = selectedIntent == intent
        return Button {
            selectedIntent = intent
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(intent.title).font(.system(.subheadline, design: .rounded)).fontWeight(.semibold).foregroundStyle(.white)
                    Text(intent.subtitle).font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(WatchColor.cadence).font(.body)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .neutralWatchSurface(isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    private var targetPacePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TARGET PACE OVERRIDE")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            Picker("Target Pace", selection: $selectedPaceOption) {
                ForEach(WatchTargetPaceOption.allOptions) { option in
                    Text(option.label(useMetric: useMetricSystem)).tag(option)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 60)
            .neutralWatchSurface(isSelected: false)
        }
    }
}

// MARK: - View Extension

private extension View {
    func neutralWatchSurface(isSelected: Bool, cornerRadius: CGFloat = 12) -> some View {
        self
            .background(Color.white.opacity(isSelected ? 0.14 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.35 : 0.08), lineWidth: 0.75)
            )
    }
}
