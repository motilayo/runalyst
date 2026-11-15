import RunalystCore
import SwiftUI

// MARK: - Watch Metrics View

/// High-contrast 2x2 Sweat-Proof biometric grid and linear pace gauge on watchOS.
/// Strictly hollow view rendering pre-formatted values from `PacingDisplayState`.
public struct WatchMetricsView: View {
    @Environment(PacingViewModel.self) private var pacingViewModel
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric

    public init() {}

    private var displayState: PacingDisplayState {
        pacingViewModel.displayState
    }

    private var trackSnapshot: LiveTrackSnapshot? {
        pacingViewModel.latestTrackSnapshot
    }

    public var body: some View {
        VStack(spacing: 4) {
            headerBar

            dynamicPaceGauge
                .padding(.vertical, 1)

            metricsGrid
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Pace \(displayState.filteredPaceFormatted(useMetric: useMetricSystem)), Cadence \(displayState.filteredCadenceFormatted), Heart Rate \(displayState.filteredHeartRateFormatted)."
        )
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            if let blockRemaining = displayState.activeBlockRemainingFormatted, !blockRemaining.isEmpty {
                HStack(spacing: 4) {
                    Text((displayState.activeBlockBadge ?? "BLOCK").uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(WatchColor.surgeTeal)
                    Text(blockRemaining)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .foregroundStyle(.secondary)
                }
            } else if !displayState.refractoryCountdownFormatted.isEmpty {
                HStack(spacing: 4) {
                    Text("COOLDOWN")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(WatchColor.recoverAmber)
                    Text(displayState.refractoryCountdownFormatted)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .foregroundStyle(.secondary)
                }
            } else if displayState.isCalibrating {
                HStack(spacing: 4) {
                    Text("BASELINE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(WatchColor.calibratingBlue)
                    Text(displayState.calibrationProgressFormatted)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } else if !displayState.deviationTitle.isEmpty {
                Text(displayState.deviationTitle.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(WatchColor.pace)
            } else {
                Text(displayState.stateTitle.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(displayState.elapsedTimeFormatted)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Dynamic Pace Gauge

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
                    .frame(height: 6)

                Capsule()
                    .fill(WatchColor.cadence.opacity(0.40))
                    .frame(width: bandWidth, height: 6)
                    .offset(x: bandStart)

                Rectangle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 1.5, height: 12)
                    .offset(x: width * 0.5 - 0.75)

                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(WatchColor.pace, lineWidth: 1.5))
                    .offset(x: max(0, min(width - 12, markerX - 6)))
            }
        }
        .frame(height: 12)
    }

    // MARK: - 2x2 Metrics Grid

    private var metricsGrid: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                metricCell(
                    title: "PACE",
                    icon: WatchIcon.pace,
                    value: "\(displayState.compactFilteredPaceValue(useMetric: useMetricSystem)) \(displayState.paceUnitLabel(useMetric: useMetricSystem))",
                    subtitle: "Target \(displayState.compactTargetPaceValue(useMetric: useMetricSystem))",
                    color: WatchColor.pace
                )

                metricCell(
                    title: "CADENCE",
                    icon: WatchIcon.cadence,
                    value: displayState.filteredCadenceFormatted,
                    subtitle: displayState.targetCadenceSPM != nil ? "Target \(displayState.targetCadenceFormatted)" : nil,
                    color: WatchColor.cadence
                )
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 4) {
                metricCell(
                    title: "HEART RATE",
                    icon: WatchIcon.heartRate,
                    value: displayState.filteredHeartRateFormatted,
                    subtitle: nil,
                    color: WatchColor.heartRate
                )

                metricCell(
                    title: trackSnapshot != nil ? "LAP TIME" : "ELAPSED",
                    icon: "stopwatch.fill",
                    value: trackSnapshot?.lapElapsedFormatted ?? displayState.elapsedTimeFormatted,
                    subtitle: trackSnapshot?.totalDistanceFormatted ?? displayState.elapsedTimeFormatted,
                    color: .white
                )
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func metricCell(
        title: String,
        icon: String,
        value: String,
        subtitle: String?,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(color)

                Text(title)
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.5)
        )
    }
}
