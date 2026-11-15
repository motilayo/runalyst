import HealthKit
import RunalystCore
import SwiftUI

// MARK: - Watch Controls View

/// Left-swipe companion workout controls for Pause/Resume, End Run, and Voice Cues.
/// Strictly hollow view with accessible >=38-44pt hit targets.
public struct WatchControlsView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Binding public var voiceCuesEnabled: Bool
    public var onRequestEndWorkout: () -> Void

    public init(
        voiceCuesEnabled: Binding<Bool>,
        onRequestEndWorkout: @escaping () -> Void
    ) {
        self._voiceCuesEnabled = voiceCuesEnabled
        self.onRequestEndWorkout = onRequestEndWorkout
    }

    private var isPaused: Bool {
        workoutManager.sessionState == .paused
    }

    public var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                // Pause / Resume Control Tile
                Button {
                    if isPaused {
                        workoutManager.resumeWorkout()
                    } else {
                        workoutManager.pauseWorkout()
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 30, weight: .bold))
                        Text(isPaused ? "Resume" : "Pause")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(isPaused ? WatchColor.cadence : .yellow)
                    .frame(maxWidth: .infinity, minHeight: 70, maxHeight: .infinity)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.75)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPaused ? "Resume workout" : "Pause workout")

                // End Run Control Tile
                Button {
                    onRequestEndWorkout()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "xmark")
                            .font(.system(size: 30, weight: .bold))
                        Text("End Run")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, minHeight: 70, maxHeight: .infinity)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.75)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("End workout")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Voice Cues Toggle
            Button {
                voiceCuesEnabled.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: voiceCuesEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(voiceCuesEnabled ? WatchColor.cadence : .secondary)

                    Text(voiceCuesEnabled ? "Voice Cues On" : "Voice Cues Off")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle voice cues")
            .accessibilityValue(voiceCuesEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .horizontal)
    }
}
