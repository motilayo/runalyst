import HealthKit
import RunalystCore
import SwiftUI

// MARK: - Pacing Gauge View

/// Hollow workout gauge rendering real-time adaptive pacing state on watchOS.
/// Binds strictly to `PacingDisplayState`. Zero inline domain thresholds or calculations.
public struct PacingGaugeView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(PacingViewModel.self) private var pacingViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("watchVoiceCuesEnabled") private var voiceCuesEnabled = true
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric

    @State private var debriefPresentation: DebriefPresentation?
    @State private var isConfirmingEndWorkout = false

    public init() {}

    private var displayState: PacingDisplayState {
        pacingViewModel.displayState
    }

    private var activeAuraToken: PacingAccentToken {
        if displayState.isCalibrating {
            return .calibratingBlue
        }
        if displayState.biometricStatusToken != .neutral {
            return displayState.biometricStatusToken
        }
        return displayState.accentToken
    }

    private var accentColor: Color {
        switch displayState.accentToken {
        case .electricBlue, .surgeBlue:
            return WatchColor.pace
        case .recoverOrange:
            return WatchColor.recoverOrange
        case .neonPink:
            return WatchColor.heartRate
        case .vibrantGreen:
            return WatchColor.cadence
        case .calibratingBlue:
            return WatchColor.calibratingBlue
        case .surgeTeal:
            return WatchColor.surgeTeal
        case .recoverAmber:
            return WatchColor.recoverAmber
        case .neutral:
            return .secondary
        }
    }

    private func auraColor(for token: PacingAccentToken) -> Color {
        switch token {
        case .calibratingBlue:
            return WatchColor.calibratingBlue
        case .electricBlue, .surgeBlue:
            return WatchColor.pace
        case .surgeTeal:
            return WatchColor.surgeTeal
        case .vibrantGreen:
            return WatchColor.cadence
        case .recoverAmber:
            return WatchColor.recoverAmber
        case .recoverOrange:
            return WatchColor.recoverOrange
        case .neonPink:
            return WatchColor.heartRate
        case .neutral:
            return WatchColor.pace.opacity(0.3)
        }
    }

    private var stateColor: Color {
        auraColor(for: activeAuraToken)
    }

    private var stateIconName: String {
        if displayState.isCalibrating {
            return "waveform.path.ecg"
        }
        switch displayState.state {
        case .surge:
            return "bolt.fill"
        case .recover:
            return "heart.fill"
        default:
            return WatchIcon.pace
        }
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 7) {
                if displayState.isCalibrating {
                    calibrationHeroCard
                } else {
                    flowHeroCard
                }

                controlsRow
            }
            .padding(.horizontal, 8)

            splitProgressBezel
        }
        .navigationBarBackButtonHidden(true)
        .confirmationDialog("End Run?", isPresented: $isConfirmingEndWorkout, titleVisibility: .visible) {
            Button("End Run", role: .destructive) {
                Task {
                    let debrief = await workoutManager.endWorkout() ?? pacingViewModel.completedDebrief
                    if let debrief {
                        debriefPresentation = DebriefPresentation(debrief: debrief)
                    } else {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(item: $debriefPresentation) { item in
            RunSummaryView(debrief: item.debrief) {
                debriefPresentation = nil
                dismiss()
            }
        }
        .onChange(of: pacingViewModel.completedDebrief) { _, newDebrief in
            if let newDebrief, debriefPresentation == nil {
                debriefPresentation = DebriefPresentation(debrief: newDebrief)
            }
        }
    }

    // MARK: - Hero Cards

    private var flowHeroCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            heroHeaderRow {
                if !displayState.refractoryCountdownFormatted.isEmpty {
                    HStack(spacing: 4) {
                        Text(displayState.refractoryCountdownFormatted)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())

                        Text(displayState.elapsedTimeFormatted)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(displayState.elapsedTimeFormatted)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(displayState.compactFilteredPaceValue(useMetric: useMetricSystem))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)

                    Text(displayState.paceUnitLabel(useMetric: useMetricSystem))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    if !displayState.deviationTitle.isEmpty {
                        Text(displayState.deviationTitle.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(accentColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }

                dynamicPaceGauge
            }

            insetStatBar {
                heroStatColumn(
                    icon: WatchIcon.heartRate,
                    label: "HR",
                    value: displayState.filteredHeartRateFormatted,
                    iconColor: WatchColor.heartRate
                )
                Divider().frame(height: 18).opacity(0.25)
                heroStatColumn(
                    icon: WatchIcon.cadence,
                    label: "CADENCE",
                    value: displayState.filteredCadenceFormatted,
                    iconColor: WatchColor.cadence
                )
                Divider().frame(height: 18).opacity(0.25)
                heroStatColumn(
                    icon: WatchIcon.pace,
                    label: "TARGET",
                    value: displayState.targetPaceFormatted(useMetric: useMetricSystem),
                    iconColor: WatchColor.pace
                )
            }
        }
        .padding(10)
        .watchLiquidGlass(accent: stateColor, cornerRadius: 14, isProminent: true)
    }

    private var calibrationHeroCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            heroHeaderRow {
                Text(displayState.calibrationProgressFormatted)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(displayState.elapsedTimeFormatted)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)

                    Text("BASELINE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                calibrationProgressBar
            }

            insetStatBar {
                heroStatColumn(
                    icon: WatchIcon.pace,
                    label: "PACE",
                    value: displayState.filteredPaceFormatted(useMetric: useMetricSystem),
                    iconColor: WatchColor.pace
                )
                Divider().frame(height: 18).opacity(0.25)
                heroStatColumn(
                    icon: WatchIcon.heartRate,
                    label: "HR",
                    value: displayState.filteredHeartRateFormatted,
                    iconColor: WatchColor.heartRate
                )
                Divider().frame(height: 18).opacity(0.25)
                heroStatColumn(
                    icon: WatchIcon.cadence,
                    label: "CADENCE",
                    value: displayState.filteredCadenceFormatted,
                    iconColor: WatchColor.cadence
                )
            }
        }
        .padding(10)
        .watchLiquidGlass(accent: stateColor, cornerRadius: 14, isProminent: true)
    }

    // MARK: - Subviews & Helpers

    private func insetStatBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            content()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .padding(.top, 2)
    }

    private func heroHeaderRow<Trailing: View>(@ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(stateColor.opacity(0.15))
                    .frame(width: 20, height: 20)
                Image(systemName: stateIconName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(stateColor)
            }

            let statusTitle = displayState.biometricStatusLabel.isEmpty
                ? displayState.stateTitle
                : displayState.biometricStatusLabel
            Text(statusTitle.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(stateColor)

            Spacer()

            trailing()
        }
    }

    private func heroStatColumn(icon: String, label: String, value: String, iconColor: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(iconColor)
                Text(label)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }

    private var calibrationProgressBar: some View {
        GeometryReader { geo in
            let progress = min(max(displayState.calibrationProgress ?? 0.0, 0.0), 1.0)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 4)

                Capsule()
                    .fill(WatchColor.calibratingBlue)
                    .frame(width: geo.size.width * CGFloat(progress), height: 4)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Dynamic Pace Gauge Track

    private var dynamicPaceGauge: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let lower = min(max(displayState.targetBandLowerNormalized, 0.0), 1.0)
            let upper = min(max(displayState.targetBandUpperNormalized, 0.0), 1.0)
            let bandWidth = max(0, upper - lower) * width
            let bandStart = lower * width
            let markerX = min(max(displayState.paceGaugeNormalizedPosition, 0.0), 1.0) * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 4)

                Capsule()
                    .fill(WatchColor.cadence.opacity(0.40))
                    .frame(width: bandWidth, height: 4)
                    .offset(x: bandStart)

                Rectangle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 1, height: 8)
                    .offset(x: width * 0.5 - 0.5)

                Circle()
                    .fill(.white)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(WatchColor.pace, lineWidth: 1.5))
                    .offset(x: max(0, min(width - 8, markerX - 4)))
            }
        }
        .frame(height: 8)
    }

    // MARK: - Peripheral Split-Progress Bezel

    private var splitProgressBezel: some View {
        let token = activeAuraToken
        let color = auraColor(for: token)
        let progress = displayState.splitProgressFraction(useMetric: useMetricSystem)

        return GeometryReader { geo in
            let dot = PacingDisplayState.bezelPerimeterPoint(
                progress: progress,
                width: Double(geo.size.width),
                height: Double(geo.size.height),
                cornerRadius: 38.0,
                inset: 2.5
            )
            ZStack {
                WatchBezelTrackShape(cornerRadius: 38, inset: 2.5)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1.5)

                if progress > 0 {
                    WatchBezelTrackShape(cornerRadius: 38, inset: 2.5)
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(
                            color.opacity(0.55),
                            style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                        )
                }

                ZStack {
                    Circle()
                        .fill(color.opacity(0.35))
                        .frame(width: 9, height: 9)
                    Circle()
                        .fill(.white)
                        .frame(width: 4.5, height: 4.5)
                        .overlay(Circle().stroke(color, lineWidth: 1.5))
                }
                .position(x: dot.x, y: dot.y)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Primary Controls

    private var controlsRow: some View {
        HStack(spacing: 6) {
            Button {
                if workoutManager.sessionState == .running {
                    workoutManager.pauseWorkout()
                } else if workoutManager.sessionState == .paused {
                    workoutManager.resumeWorkout()
                }
            } label: {
                controlTile(
                    icon: workoutManager.sessionState == .paused ? "play.fill" : "pause.fill",
                    tint: .orange
                )
            }
            .buttonStyle(.plain)

            Button {
                isConfirmingEndWorkout = true
            } label: {
                controlTile(icon: "xmark", tint: .red)
            }
            .buttonStyle(.plain)

            Button {
                voiceCuesEnabled.toggle()
            } label: {
                controlTile(
                    icon: voiceCuesEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    tint: voiceCuesEnabled ? .white : .secondary
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func controlTile(icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
            )
    }
}

// MARK: - Debrief Presentation Wrapper

private struct DebriefPresentation: Identifiable {
    let id = UUID()
    let debrief: WatchRunDebrief
}
