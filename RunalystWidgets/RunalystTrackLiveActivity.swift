import ActivityKit
import AppIntents
import RunalystCore
import SwiftUI
import WidgetKit

@main
struct RunalystWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RunalystTrackLiveActivity()
    }
}

// MARK: - Runalyst Track Live Activity Widget

/// ActivityConfiguration driving Lock Screen Live Activities and Dynamic Island presentations.
struct RunalystTrackLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunalystTrackActivityAttributes.self) { context in
            LockScreenLiveActivityRootView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.snapshot.filteredPaceFormatted)
                            .font(.system(.subheadline, design: .rounded).bold().monospacedDigit())
                            .foregroundStyle(Color(token: .electricBlue))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if !context.state.snapshot.targetPaceFormatted.isEmpty && context.state.snapshot.targetPaceFormatted != "--" {
                            Text(context.state.snapshot.targetPaceFormatted)
                                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.snapshot.filteredCadenceFormatted)
                            .font(.system(.subheadline, design: .rounded).bold().monospacedDigit())
                            .foregroundStyle(Color(token: .vibrantGreen))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(context.state.snapshot.filteredHeartRateFormatted)
                            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color(token: .neonPink))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.snapshot.trackSnapshot?.lapHeaderLabel ?? context.state.snapshot.headerTitle)
                        .font(.system(.caption2, design: .rounded).bold())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        DynamicIslandTrackDotView(
                            lapProgress: context.state.snapshot.trackSnapshot?.lapProgress ?? 0.0,
                            ghostProgress: context.state.snapshot.phase == .calibrating ? nil : context.state.snapshot.trackSnapshot?.ghostProgress,
                            statusToken: context.state.snapshot.biometricStatusToken,
                            isPaused: context.state.snapshot.isPaused
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)

                        HStack {
                            Text(context.state.snapshot.biometricStatusLabel)
                                .font(.system(.caption2, design: .rounded).weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer()
                            Text(context.state.snapshot.elapsedTimeFormatted)
                                .font(.system(.caption2, design: .rounded).bold().monospacedDigit())
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
            } compactLeading: {
                Text(context.state.snapshot.filteredPaceFormatted)
                    .font(.system(.caption2, design: .rounded).bold().monospacedDigit())
                    .foregroundStyle(Color(token: .electricBlue))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } compactTrailing: {
                Text(context.state.snapshot.filteredCadenceFormatted)
                    .font(.system(.caption2, design: .rounded).bold().monospacedDigit())
                    .foregroundStyle(Color(token: .vibrantGreen))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } minimal: {
                Circle()
                    .fill(Color(token: context.state.snapshot.biometricStatusToken))
                    .frame(width: 10, height: 10)
            }
        }
    }
}

// MARK: - Lock Screen Live Activity Root View

private struct LockScreenLiveActivityRootView: View {
    let context: ActivityViewContext<RunalystTrackActivityAttributes>

    var body: some View {
        if context.state.snapshot.phase == .completed, let debrief = context.state.snapshot.completedDebrief {
            completedDebriefView(debrief: debrief)
        } else {
            activeWorkoutView(snapshot: context.state.snapshot, displayMode: context.state.displayMode, isWatchReachable: context.state.isWatchReachable)
        }
    }

    // MARK: - Active Workout View

    @ViewBuilder
    private func activeWorkoutView(snapshot: WatchLiveRunSnapshot, displayMode: LiveActivityDisplayMode, isWatchReachable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            // Compact Single-Line Header Row: Title, Subtitle, Cumulative Distance, Elapsed Time
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(snapshot.headerTitle)
                    .font(.system(.subheadline, design: .rounded).bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("• \(snapshot.headerTitle == snapshot.runIntent.title ? (snapshot.location == .indoor ? "Indoor" : "Outdoor") : snapshot.intentAndLocationSubtitle)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                if let dist = snapshot.trackSnapshot?.totalDistanceFormatted {
                    Text(dist)
                        .font(.system(.caption2, design: .rounded).monospacedDigit().bold())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(snapshot.elapsedTimeFormatted)
                    .font(.system(.subheadline, design: .rounded).monospacedDigit().bold())
                    .foregroundStyle(snapshot.phase == .paused ? Color(token: .recoverOrange) : .primary)
                    .lineLimit(1)
            }

            // Mode-Switched Lock Screen Presentation View
            switch displayMode {
            case .track:
                LiveActivityTrackView(snapshot: snapshot)
            case .metrics:
                LiveActivityMetricsView(snapshot: snapshot)
            case .chart:
                LiveActivityChartView(snapshot: snapshot)
            }

            // Interactive Bar (36pt minHeight for Lock Screen height budget)
            HStack(spacing: 8) {
                Button(intent: CycleLiveActivityViewIntent()) {
                    Label("Next: \(displayMode.nextMode.title)", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(.caption, design: .rounded).bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                Button(intent: ToggleWatchWorkoutPauseIntent()) {
                    remoteControlButtonLabel(isPaused: snapshot.phase == .paused, isReachable: isWatchReachable)
                        .font(.system(.caption, design: .rounded).bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .tint(!isWatchReachable ? .secondary : (snapshot.phase == .paused ? .green : .orange))
                .disabled(!isWatchReachable)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .activityBackgroundTint(Color.black.opacity(0.85))
        .activitySystemActionForegroundColor(.white)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func remoteControlButtonLabel(isPaused: Bool, isReachable: Bool) -> some View {
        if !isReachable {
            Label("Watch Offline", systemImage: "applewatch.slash")
        } else if isPaused {
            Label("Resume", systemImage: "play.fill")
        } else {
            Label("Pause", systemImage: "pause.fill")
        }
    }

    // MARK: - Completed Debrief View

    @ViewBuilder
    private func completedDebriefView(debrief: WatchRunDebrief) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color(token: .vibrantGreen))
                Text(debrief.companionSyncBadgeText)
                    .font(.system(.subheadline, design: .rounded).bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Text(debrief.companionSyncSubtitle)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack {
                summaryTile(label: "TIME", value: debrief.elapsedFormatted)
                Spacer()
                summaryTile(label: "DIST", value: debrief.distanceFormatted)
                Spacer()
                summaryTile(label: "AVG PACE", value: debrief.averagePaceFormatted, color: Color(token: .electricBlue))
                Spacer()
                summaryTile(label: "AVG HR", value: debrief.averageHeartRateFormatted, color: Color(token: .neonPink))
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 3) {
                bulletRow(icon: "waveform.path.ecg", text: debrief.adaptationsBullet)
                bulletRow(icon: "heart.fill", text: debrief.efficiencyScoreBullet)
                bulletRow(icon: "metronome.fill", text: debrief.formInsightBullet)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .activityBackgroundTint(Color.black.opacity(0.85))
        .activitySystemActionForegroundColor(.white)
        .environment(\.colorScheme, .dark)
    }

    private func summaryTile(label: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func bulletRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
