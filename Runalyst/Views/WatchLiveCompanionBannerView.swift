import RunalystCore
import SwiftUI

/// Hollow view rendering real-time companion workout telemetry and post-run debrief from Apple Watch.
///
/// Adheres strictly to the Hollow Foundry doctrine:
/// - Zero biomechanical thresholds, math, or duration calculations.
/// - Pure read-only renderer over `WatchLiveRunSnapshot` and `WatchRunDebrief`.
/// - Cross-device adaptive layout: 3-column side-by-side on iPad (`.regular`), swipeable TabView on iPhone (`.compact`).
/// - Sweaty Hands UX: >= 44pt hit targets, monospaced digits, and SF Pro Rounded fonts.
struct WatchLiveCompanionBannerView: View {
    let bridge: WatchCalibrationBridge
    let onSyncRequested: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedPage: LiveActivityDisplayMode = .track

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
                    .foregroundColor(snapshot.phase == .paused ? .orange : Color(token: .electricBlue))

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
                        .fill(Color(token: snapshot.biometricStatusToken))
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

            // Cross-Device Adaptive Layout: iPad 3-Column vs iPhone Swipe Pager
            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 12) {
                    CompanionTrackPageView(snapshot: snapshot)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color(UIColor.tertiarySystemFill).opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    CompanionMetricsPageView(snapshot: snapshot)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color(UIColor.tertiarySystemFill).opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    CompanionChartPageView(snapshot: snapshot)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color(UIColor.tertiarySystemFill).opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            } else {
                swipePager(snapshot: snapshot)
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

    // MARK: - iPhone Swipe Pager & Indicator

    @ViewBuilder
    private func swipePager(snapshot: WatchLiveRunSnapshot) -> some View {
        VStack(spacing: 8) {
            TabView(selection: $selectedPage) {
                CompanionTrackPageView(snapshot: snapshot)
                    .tag(LiveActivityDisplayMode.track)

                CompanionMetricsPageView(snapshot: snapshot)
                    .tag(LiveActivityDisplayMode.metrics)

                CompanionChartPageView(snapshot: snapshot)
                    .tag(LiveActivityDisplayMode.chart)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 185)

            pageIndicator
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(LiveActivityDisplayMode.allCases, id: \.self) { mode in
                Circle()
                    .fill(selectedPage == mode ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedPage = mode
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(selectedPage.title)")
    }

    // MARK: - Completed Debrief Card

    @ViewBuilder
    private func completedDebriefCard(debrief: WatchRunDebrief) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Row
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(Color(token: .vibrantGreen))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Just Finished on Apple Watch")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text("Run Debrief")
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                Spacer()

                Button {
                    bridge.dismissCompletedDebrief()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss Run Debrief")
            }

            // Summary Strip: Elapsed, Distance, Avg Pace, Avg HR
            HStack {
                metricTile(label: "Time", value: debbriefMetricTime(debrief), color: .primary)
                Spacer()
                metricTile(label: "Distance", value: debrief.distanceFormatted, color: .primary)
                Spacer()
                metricTile(label: "Avg Pace", value: debrief.averagePaceFormatted, color: Color(token: .electricBlue))
                Spacer()
                metricTile(label: "Avg HR", value: debrief.averageHeartRateFormatted, color: Color(token: .neonPink))
            }
            .padding(.vertical, 4)

            Divider()

            // 3 Takeaway Bullets
            VStack(alignment: .leading, spacing: 8) {
                takeawayRow(
                    icon: "waveform.path.ecg",
                    title: "Adaptations",
                    text: debrief.adaptationsBullet,
                    color: Color(token: .electricBlue)
                )
                takeawayRow(
                    icon: "heart.fill",
                    title: "Efficiency",
                    text: debrief.efficiencyScoreBullet,
                    color: Color(token: .neonPink)
                )
                takeawayRow(
                    icon: "metronome.fill",
                    title: "Form Insight",
                    text: debrief.formInsightBullet,
                    color: Color(token: .vibrantGreen)
                )
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
        .task(id: debrief) {
            onSyncRequested()
        }
    }

    // MARK: - Reusable Tile Helpers

    private func debbriefMetricTime(_ debrief: WatchRunDebrief) -> String {
        debrief.elapsedFormatted
    }

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
