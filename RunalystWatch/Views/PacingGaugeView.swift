import HealthKit
import RunalystCore
import SwiftUI

// MARK: - Pacing Gauge View

/// Hollow workout gauge rendering real-time adaptive pacing state on watchOS.
///
/// Binds strictly to `PacingDisplayState`. Zero inline domain thresholds or calculations.
public struct PacingGaugeView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(PacingViewModel.self) private var pacingViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("watchVoiceCuesEnabled") private var voiceCuesEnabled = true

    @State private var debriefPresentation: DebriefPresentation?
    @State private var isPulsing = false

    public init() {}

    private var displayState: PacingDisplayState {
        pacingViewModel.displayState
    }

    private let electricBlue = Color(red: 0.0, green: 0.8, blue: 1.0)
    private let neonPink = Color(red: 1.0, green: 0.18, blue: 0.58)
    private let vibrantGreen = Color(red: 0.18, green: 0.85, blue: 0.35)
    private let surgeTeal = Color(red: 0.0, green: 0.9, blue: 0.75)
    private let recoverAmber = Color(red: 1.0, green: 0.65, blue: 0.1)
    private let recoverOrange = Color(red: 1.0, green: 0.58, blue: 0.0)
    private let calibratingBlue = Color(red: 0.2, green: 0.6, blue: 1.0)

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
            return electricBlue
        case .recoverOrange:
            return recoverOrange
        case .neonPink:
            return neonPink
        case .vibrantGreen:
            return vibrantGreen
        case .calibratingBlue:
            return calibratingBlue
        case .surgeTeal:
            return surgeTeal
        case .recoverAmber:
            return recoverAmber
        case .neutral:
            return .secondary
        }
    }

    private func auraColor(for token: PacingAccentToken) -> Color {
        switch token {
        case .calibratingBlue:
            return calibratingBlue
        case .electricBlue, .surgeBlue:
            return electricBlue
        case .surgeTeal:
            return surgeTeal
        case .vibrantGreen:
            return vibrantGreen
        case .recoverAmber:
            return recoverAmber
        case .recoverOrange:
            return recoverOrange
        case .neonPink:
            return neonPink
        case .neutral:
            return electricBlue.opacity(0.3)
        }
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if displayState.isCalibrating {
                calibrationBody
            } else {
                flowBody
            }

            biometricEdgeAura
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .fullScreenCover(item: $debriefPresentation) { item in
            RunSummaryView(debrief: item.debrief) {
                debriefPresentation = nil
                dismiss()
            }
        }
    }

    // MARK: - Calibration Layout

    private var calibrationBody: some View {
        VStack(spacing: 4) {
            // Top status
            HStack {
                Text(displayState.biometricStatusLabel.isEmpty ? "Calibrating" : displayState.biometricStatusLabel)
                    .font(.system(.caption2, design: .rounded))
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(calibratingBlue.opacity(0.2))
                    .foregroundStyle(calibratingBlue)
                    .clipShape(Capsule())

                Spacer()

                Text(displayState.calibrationProgressFormatted)
                    .font(.system(.caption2, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            // Elapsed time (large monospaced)
            VStack(spacing: 1) {
                Text(displayState.elapsedTimeFormatted)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(calibratingBlue)

                Text("READING BASELINE")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Smooth calibration progress bar
            GeometryReader { geo in
                let progress = min(max(displayState.calibrationProgress ?? 0.0, 0.0), 1.0)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 5)

                    Capsule()
                        .fill(calibratingBlue)
                        .frame(width: geo.size.width * CGFloat(progress), height: 5)
                }
            }
            .frame(height: 5)
            .padding(.horizontal, 4)

            // Secondary metrics strip (PACE, HR, CADENCE)
            HStack(spacing: 4) {
                VStack(alignment: .center, spacing: 1) {
                    Text("PACE")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(displayState.filteredPaceFormatted)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .foregroundStyle(electricBlue)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 14)

                VStack(alignment: .center, spacing: 1) {
                    Text("HR")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(displayState.filteredHeartRateFormatted)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .foregroundStyle(neonPink)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 14)

                VStack(alignment: .center, spacing: 1) {
                    Text("CADENCE")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(displayState.filteredCadenceFormatted)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .foregroundStyle(vibrantGreen)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 2)

            // Controls
            controlsRow
        }
        .padding(.top, 16)
        .padding(.horizontal, 10)
    }

    // MARK: - In The Flow Layout

    private var flowBody: some View {
        VStack(spacing: 4) {
            // 1. Top pill row
            HStack {
                if !displayState.biometricStatusLabel.isEmpty {
                    Text(displayState.biometricStatusLabel)
                        .font(.system(.caption2, design: .rounded))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(auraColor(for: activeAuraToken).opacity(0.2))
                        .foregroundStyle(auraColor(for: activeAuraToken))
                        .clipShape(Capsule())
                } else {
                    Text(displayState.stateTitle)
                        .font(.system(.caption2, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(accentColor)
                }

                Spacer()

                if !displayState.refractoryCountdownFormatted.isEmpty {
                    Text(displayState.refractoryCountdownFormatted)
                        .font(.system(.caption2, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.12))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                } else {
                    Text(displayState.elapsedTimeFormatted)
                        .font(.system(.caption2, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

            // 2. Dynamic Pace Gauge
            dynamicPaceGauge
                .padding(.vertical, 1)

            // 3. Primary Metrics: Pace & deviation
            VStack(spacing: 1) {
                Text(displayState.filteredPaceFormatted)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(electricBlue)

                if !displayState.deviationTitle.isEmpty {
                    Text(displayState.deviationTitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(accentColor)
                }
            }

            // HR, Cadence, Target strip
            HStack(spacing: 4) {
                VStack(alignment: .center, spacing: 1) {
                    Text("HR")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(displayState.filteredHeartRateFormatted)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .foregroundStyle(neonPink)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 14)

                VStack(alignment: .center, spacing: 1) {
                    Text("CADENCE")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(displayState.filteredCadenceFormatted)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .foregroundStyle(vibrantGreen)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 14)

                VStack(alignment: .center, spacing: 1) {
                    Text("TARGET")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(displayState.targetPaceFormatted)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .foregroundStyle(electricBlue)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 2)

            // Controls
            controlsRow
        }
        .padding(.top, 16)
        .padding(.horizontal, 10)
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
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 5)

                // Sweet-spot green band
                Capsule()
                    .fill(vibrantGreen.opacity(0.45))
                    .frame(width: bandWidth, height: 5)
                    .offset(x: bandStart)

                // Center target tick mark
                Rectangle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 2, height: 9)
                    .offset(x: width * 0.5 - 1)

                // Live marker dot (Electric Blue with glow)
                Circle()
                    .fill(electricBlue)
                    .frame(width: 11, height: 11)
                    .shadow(color: electricBlue.opacity(0.85), radius: 3)
                    .offset(x: markerX - 5.5)
            }
        }
        .frame(height: 11)
        .padding(.horizontal, 4)
    }

    // MARK: - Biometric Edge Aura

    private var biometricEdgeAura: some View {
        let token = activeAuraToken
        let color = auraColor(for: token)
        let isCalibrating = displayState.isCalibrating || token == .calibratingBlue
        let strokeOpacity: Double = {
            if isCalibrating {
                return isPulsing ? 0.95 : 0.4
            }
            switch token {
            case .surgeTeal, .vibrantGreen, .recoverAmber, .recoverOrange:
                return 0.85
            case .electricBlue, .surgeBlue:
                return 0.6
            default:
                return 0.25
            }
        }()
        let shadowRadius: CGFloat = {
            if isCalibrating {
                return isPulsing ? 8 : 4
            }
            switch token {
            case .surgeTeal, .vibrantGreen, .recoverAmber, .recoverOrange:
                return 6
            default:
                return 3
            }
        }()

        return RoundedRectangle(cornerRadius: 38)
            .strokeBorder(color.opacity(strokeOpacity), lineWidth: 3.5)
            .shadow(color: color.opacity(strokeOpacity * 0.7), radius: shadowRadius)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    // MARK: - Primary Controls

    private var controlsRow: some View {
        HStack(spacing: 12) {
            // Pause / Resume
            Button {
                if workoutManager.sessionState == .running {
                    workoutManager.pauseWorkout()
                } else if workoutManager.sessionState == .paused {
                    workoutManager.resumeWorkout()
                }
            } label: {
                Image(systemName: workoutManager.sessionState == .paused ? "play.fill" : "pause.fill")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Color.yellow.opacity(0.3))
                    .foregroundStyle(.yellow)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // End Session
            Button {
                Task {
                    let debrief = await workoutManager.endWorkout() ?? pacingViewModel.completedDebrief
                    if let debrief {
                        debriefPresentation = DebriefPresentation(debrief: debrief)
                    } else {
                        dismiss()
                    }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Color.red.opacity(0.3))
                    .foregroundStyle(.red)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // Voice Cues Toggle
            Button {
                voiceCuesEnabled.toggle()
            } label: {
                Image(systemName: voiceCuesEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.body)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Color.gray.opacity(0.3))
                    .foregroundStyle(voiceCuesEnabled ? .green : .secondary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Debrief Presentation Wrapper

private struct DebriefPresentation: Identifiable {
    let id = UUID()
    let debrief: WatchRunDebrief
}
