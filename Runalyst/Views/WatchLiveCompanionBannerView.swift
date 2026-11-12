import SwiftUI
import RunalystCore

/// Hollow view rendering real-time companion workout telemetry and post-run debrief from Apple Watch.
///
/// Adheres strictly to the Hollow Foundry doctrine:
/// - Zero biomechanical thresholds, math, or duration calculations.
/// - Pure read-only renderer over `WatchLiveRunSnapshot` and `WatchRunDebrief`.
/// - Sweaty Hands UX: >= 44pt hit targets, monospaced digits, and SF Pro Rounded fonts.
struct WatchLiveCompanionBannerView: View {
    let bridge: WatchCalibrationBridge
    let onSyncRequested: () -> Void

    var body: some View {
        if let snapshot = bridge.latestWatchSnapshot, snapshot.isActiveWorkout {
            activeCompanionCard(snapshot: snapshot)
        } else if let debrief = bridge.latestCompletedDebrief {
            completedDebriefCard(debrief: debrief)
        } else {
            EmptyView()
        }
    }

    // MARK: - Active Workout Companion Card

    @ViewBuilder
    private func activeCompanionCard(snapshot: WatchLiveRunSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row: Watch Icon, Title, Subtitle, Elapsed Time & State
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "applewatch")
                    .font(.title3)
                    .foregroundColor(snapshot.phase == .paused ? .orange : RunalystColor.pace)

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.headerTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(snapshot.intentAndLocationSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(snapshot.elapsedTimeFormatted)
                        .font(.system(.subheadline, design: .rounded).bold())
                        .monospacedDigit()
                        .foregroundColor(.primary)
                    Text(snapshot.stateTitle)
                        .font(.caption2.bold())
                        .foregroundColor(snapshot.phase == .paused ? .orange : .secondary)
                }
            }

            // Biometric Status & Deviation Badges
            if !snapshot.biometricStatusLabel.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(snapshot.biometricStatusToken.color)
                        .frame(width: 8, height: 8)
                    Text(snapshot.biometricStatusLabel)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    if !snapshot.deviationTitle.isEmpty {
                        Text(snapshot.deviationTitle)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Target Pace Normalized Bar Gauge
            paceGaugeBar(snapshot: snapshot)

            // Live Metrics Row: Pace, Target, HR, Cadence
            HStack {
                metricTile(label: "Pace", value: snapshot.filteredPaceFormatted, color: RunalystColor.pace)
                Spacer()
                metricTile(label: "Target", value: snapshot.targetPaceFormatted, color: .secondary)
                Spacer()
                metricTile(label: "Heart Rate", value: snapshot.filteredHeartRateFormatted, color: RunalystColor.heartRate)
                Spacer()
                metricTile(label: "Cadence", value: snapshot.filteredCadenceFormatted, color: RunalystColor.cadence)
            }

            // Sweaty Hands Remote Control Actions
            HStack(spacing: 12) {
                Button {
                    if snapshot.phase == .paused {
                        bridge.sendRemoteCommand(.resumeWorkout)
                    } else {
                        bridge.sendRemoteCommand(.pauseWorkout)
                    }
                } label: {
                    Label(
                        snapshot.phase == .paused ? "Resume" : "Pause",
                        systemImage: snapshot.phase == .paused ? "play.fill" : "pause.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(snapshot.phase == .paused ? .green : .orange)
                .disabled(!bridge.isWatchReachable)

                Button(role: .destructive) {
                    bridge.sendRemoteCommand(.endWorkout)
                } label: {
                    Label("End", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(!bridge.isWatchReachable)
            }

            if !bridge.isWatchReachable {
                Text("Apple Watch unreachable")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    // MARK: - Pace Gauge Normalized Bar

    @ViewBuilder
    private func paceGaugeBar(snapshot: WatchLiveRunSnapshot) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let lower = min(max(snapshot.targetBandLowerNormalized, 0.0), 1.0)
            let upper = min(max(snapshot.targetBandUpperNormalized, lower), 1.0)
            let needle = min(max(snapshot.paceGaugeNormalizedPosition, 0.0), 1.0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(UIColor.tertiarySystemFill))
                    .frame(height: 8)

                // Target Pace Zone Band
                Capsule()
                    .fill(RunalystColor.cadence.opacity(0.45))
                    .frame(width: max(4, (upper - lower) * width), height: 8)
                    .offset(x: lower * width)

                // Current Pace Needle Marker
                Circle()
                    .fill(RunalystColor.pace)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: max(0, min(width - 14, needle * width - 7)))
            }
        }
        .frame(height: 14)
    }

    // MARK: - Completed Debrief Card

    @ViewBuilder
    private func completedDebriefCard(debrief: WatchRunDebrief) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Row
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(RunalystColor.cadence)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Just Finished on Apple Watch")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text("Coach's Takeaway")
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                Spacer()
            }

            // Summary Strip: Elapsed, Distance, Avg Pace, Avg HR
            HStack {
                metricTile(label: "Time", value: debrief.elapsedFormatted, color: .primary)
                Spacer()
                metricTile(label: "Distance", value: debrief.distanceFormatted, color: .primary)
                Spacer()
                metricTile(label: "Avg Pace", value: debrief.averagePaceFormatted, color: RunalystColor.pace)
                Spacer()
                metricTile(label: "Avg HR", value: debrief.averageHeartRateFormatted, color: RunalystColor.heartRate)
            }
            .padding(.vertical, 4)

            Divider()

            // 3 Takeaway Bullets
            VStack(alignment: .leading, spacing: 8) {
                takeawayRow(icon: "waveform.path.ecg", title: "Adaptations", text: debrief.adaptationsBullet, color: RunalystColor.pace)
                takeawayRow(icon: "heart.fill", title: "Efficiency", text: debrief.efficiencyScoreBullet, color: RunalystColor.heartRate)
                takeawayRow(icon: "metronome.fill", title: "Form Insight", text: debrief.formInsightBullet, color: RunalystColor.cadence)
            }

            // Action Buttons: Dismiss & Sync Run
            HStack(spacing: 12) {
                Button {
                    bridge.dismissCompletedDebrief()
                } label: {
                    Text("Dismiss")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                Button {
                    onSyncRequested()
                    bridge.dismissCompletedDebrief()
                } label: {
                    Label("Sync Run", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(RunalystColor.pace)
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    // MARK: - Reusable Tile Helpers

    private func metricTile(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded).bold())
                .monospacedDigit()
                .foregroundColor(color)
        }
    }

    private func takeawayRow(icon: String, title: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundColor(color)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                Text(text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - PacingAccentToken Color Mapping

private extension PacingAccentToken {
    var color: Color {
        switch self {
        case .electricBlue, .surgeBlue, .calibratingBlue:
            return RunalystColor.pace
        case .neonPink:
            return RunalystColor.heartRate
        case .vibrantGreen:
            return RunalystColor.cadence
        case .recoverOrange, .recoverAmber:
            return RunalystColor.warning
        case .surgeTeal:
            return Color.teal
        case .neutral:
            return Color.secondary
        }
    }
}
