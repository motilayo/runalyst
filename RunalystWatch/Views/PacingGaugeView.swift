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

    @AppStorage("watchVoiceCuesEnabled") private var voiceCuesEnabled = false

    public init() {}

    private var displayState: PacingDisplayState {
        pacingViewModel.displayState
    }

    private var accentColor: Color {
        switch displayState.accentToken {
        case .electricBlue:
            return Color(red: 0.0, green: 0.8, blue: 1.0)
        case .neonPink:
            return Color(red: 1.0, green: 0.18, blue: 0.58)
        case .vibrantGreen:
            return Color(red: 0.2, green: 0.88, blue: 0.38)
        case .neutral:
            return .secondary
        }
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 6) {
                // Top status bar
                HStack {
                    Text(displayState.stateTitle)
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(accentColor)

                    Spacer()

                    if !displayState.refractoryCountdownFormatted.isEmpty {
                        Text(displayState.refractoryCountdownFormatted)
                            .font(.system(.caption2, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else if let calProgress = displayState.calibrationProgress, calProgress < 1.0 {
                        Text(displayState.calibrationProgressFormatted)
                            .font(.system(.caption2, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                // Current Filtered Pace
                VStack(spacing: 0) {
                    Text(displayState.filteredPaceFormatted)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)

                    Text(displayState.deviationTitle)
                        .font(.system(.caption2, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundStyle(accentColor)
                }

                // Target Pace & Heart Rate strip
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TARGET")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(displayState.targetPaceFormatted)
                            .font(.system(.callout, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }

                    Divider()
                        .frame(height: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("HEART RATE")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(displayState.filteredHeartRateFormatted)
                            .font(.system(.callout, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }
                .padding(.vertical, 4)

                // Primary Controls (minimum 44x44pt hit targets)
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
                            await workoutManager.endWorkout()
                            dismiss()
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
            .padding(.horizontal, 4)
        }
        .navigationBarBackButtonHidden(true)
    }
}
