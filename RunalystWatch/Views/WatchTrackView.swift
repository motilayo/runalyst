import RunalystCore
import SwiftUI

// MARK: - Stadium Track Shape

private struct StadiumTrackShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 96
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let point = WatchTrackView.ovalPoint(progress: progress, in: rect)
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Watch Track View

/// 3D perspective-tilted 400m stadium oval presentation on watchOS.
/// Purely hollow renderer binding directly to `LiveTrackSnapshot` and `PacingDisplayState`.
public struct WatchTrackView: View {
    @Environment(PacingViewModel.self) private var pacingViewModel
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric

    public init() {}

    private var displayState: PacingDisplayState {
        pacingViewModel.displayState
    }

    private var trackSnapshot: LiveTrackSnapshot? {
        pacingViewModel.latestTrackSnapshot
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

    private var runnerColor: Color {
        Color(token: trackSnapshot?.statusToken ?? activeAuraToken)
    }

    nonisolated static func ovalPoint(progress: Double, in rect: CGRect) -> CGPoint {
        let coord = LiveTrackCore.trackOvalPoint(progress: progress)
        // Scale from 0.84 span to 0.94 span (~94% width)
        let scaleX = 0.94 / 0.84
        let scaleY = 0.94 / 0.84
        let nx = 0.5 + (coord.x - 0.5) * scaleX
        let ny = 0.5 + (coord.y - 0.5) * scaleY
        return CGPoint(
            x: rect.minX + rect.width * CGFloat(nx),
            y: rect.minY + rect.height * CGFloat(ny)
        )
    }

    public var body: some View {
        VStack(spacing: 4) {
            headerRow

            track3DArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomMetricsStrip
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(trackSnapshot?.accessibilitySummary ?? displayState.stateTitle)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        VStack(spacing: 3) {
            if displayState.isCalibrating {
                HStack {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(WatchColor.calibratingBlue)
                            .frame(width: 7, height: 7)
                        Text("BASELINE")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(WatchColor.calibratingBlue)
                    }
                    Spacer()
                    Text(displayState.calibrationProgressFormatted)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                GeometryReader { barGeo in
                    let progress = min(max(displayState.calibrationProgress ?? 0.0, 0.0), 1.0)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 3.5)
                        Capsule()
                            .fill(WatchColor.calibratingBlue)
                            .frame(width: barGeo.size.width * CGFloat(progress), height: 3.5)
                    }
                }
                .frame(height: 3.5)
            } else {
                HStack {
                    if let badge = displayState.activeBlockBadge, !badge.isEmpty {
                        HStack(spacing: 3) {
                            Text(badge.uppercased())
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(token: activeAuraToken))
                            if let remaining = displayState.activeBlockRemainingFormatted, !remaining.isEmpty {
                                Text(remaining)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text(trackSnapshot?.lapHeaderLabel ?? "Lap 1 • 0/400m")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Spacer()

                    if let ghostLabel = trackSnapshot?.ghostDeltaLabel, !ghostLabel.isEmpty, ghostLabel != "--" {
                        Text(ghostLabel)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(token: trackSnapshot?.statusToken ?? .neutral))
                            .lineLimit(1)
                    } else {
                        Text(displayState.elapsedTimeFormatted)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 3D Perspective Track Area

    private var track3DArea: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let rect = CGRect(x: 0, y: 0, width: width, height: height)

            ZStack {
                // Stadium track baseline oval (~94% width)
                StadiumTrackShape()
                    .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))

                // Start / Finish line at top-center (progress 0.0)
                let finishPos = Self.ovalPoint(progress: 0.0, in: rect)
                Rectangle()
                    .fill(Color.white.opacity(0.40))
                    .frame(width: 2.5, height: 8)
                    .position(finishPos)

                // Ghost pacer dot (when calibrated and available)
                if !displayState.isCalibrating, let ghostProgress = trackSnapshot?.ghostProgress {
                    let ghostPos = Self.ovalPoint(progress: ghostProgress, in: rect)

                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.20))
                            .frame(width: 12, height: 12)
                        Circle()
                            .stroke(Color.white.opacity(0.70), lineWidth: 1.5)
                            .frame(width: 10, height: 10)
                    }
                    .position(ghostPos)
                }

                // Glowing biometric runner dot
                let runnerProgress = trackSnapshot?.lapProgress ?? 0.0
                let runnerPos = Self.ovalPoint(progress: runnerProgress, in: rect)

                ZStack {
                    Circle()
                        .fill(runnerColor.opacity(0.40))
                        .frame(width: 22, height: 22)
                        .blur(radius: 3)

                    Circle()
                        .fill(runnerColor)
                        .frame(width: 12, height: 12)

                    Circle()
                        .fill(.white)
                        .frame(width: 4.5, height: 4.5)
                }
                .position(runnerPos)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .rotation3DEffect(.degrees(34), axis: (x: 1, y: 0, z: 0))
        }
    }

    // MARK: - Compact Metrics Strip

    private var bottomMetricsStrip: some View {
        HStack(spacing: 0) {
            compactStatColumn(
                label: "PACE",
                value: displayState.filteredPaceFormatted(useMetric: useMetricSystem),
                color: WatchColor.pace
            )
            Divider().frame(height: 18).opacity(0.25)
            compactStatColumn(
                label: "CADENCE",
                value: displayState.filteredCadenceFormatted,
                color: WatchColor.cadence
            )
            Divider().frame(height: 18).opacity(0.25)
            compactStatColumn(
                label: "HR",
                value: displayState.filteredHeartRateFormatted,
                color: WatchColor.heartRate
            )
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 2)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func compactStatColumn(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
