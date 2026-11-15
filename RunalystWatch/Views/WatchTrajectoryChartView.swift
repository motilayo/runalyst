import RunalystCore
import SwiftUI

// MARK: - Watch Trajectory Chart View

/// Rolling trajectory chart rendering pace corridor, live traces, and recent lap splits on watchOS.
/// Purely hollow view consuming pre-normalized coordinates from `LiveTrajectorySummary`.
public struct WatchTrajectoryChartView: View {
    @Environment(PacingViewModel.self) private var pacingViewModel

    public init() {}

    private var summary: LiveTrajectorySummary? {
        pacingViewModel.latestTrajectorySummary
    }

    public var body: some View {
        VStack(spacing: 4) {
            headerRow
                .padding(.horizontal, 2)

            chartCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            recentSplitsRow
                .padding(.horizontal, 2)
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pace and heart rate trajectory chart for \(summary?.windowLabel ?? "recent workout").")
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack {
            HStack(spacing: 4) {
                Circle()
                    .fill(WatchColor.pace)
                    .frame(width: 6, height: 6)
                Text("PACE")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(WatchColor.pace)

                Circle()
                    .fill(WatchColor.heartRate)
                    .frame(width: 6, height: 6)
                    .padding(.leading, 3)
                Text("HR")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(WatchColor.heartRate)
            }

            Spacer()

            Text(summary?.windowLabel ?? "Last 8 min")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Chart Canvas

    private var chartCanvas: some View {
        Canvas { context, size in
            let insetY: CGFloat = 4
            let usableHeight = max(1, size.height - insetY * 2)
            func yPosition(for normalizedY: CGFloat) -> CGFloat {
                insetY + (1.0 - normalizedY) * usableHeight
            }

            let lowerYNorm = summary?.corridorLowerY ?? 0.42
            let upperYNorm = summary?.corridorUpperY ?? 0.58

            // Canvas Y=0 is top, so y = insetY + (1.0 - normalizedY) * usableHeight
            let topY = yPosition(for: CGFloat(upperYNorm))
            let bottomY = yPosition(for: CGFloat(lowerYNorm))
            let corridorHeight = max(2.0, bottomY - topY)
            let corridorRect = CGRect(x: 0, y: topY, width: size.width, height: corridorHeight)

            // Shaded green target corridor
            context.fill(
                Path(roundedRect: corridorRect, cornerRadius: 3),
                with: .color(WatchColor.cadence.opacity(0.18))
            )

            // Subtle corridor boundary lines
            var corridorLines = Path()
            corridorLines.move(to: CGPoint(x: 0, y: topY))
            corridorLines.addLine(to: CGPoint(x: size.width, y: topY))
            corridorLines.move(to: CGPoint(x: 0, y: bottomY))
            corridorLines.addLine(to: CGPoint(x: size.width, y: bottomY))
            context.stroke(
                corridorLines,
                with: .color(WatchColor.cadence.opacity(0.35)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )

            guard let points = summary?.points, !points.isEmpty else {
                return
            }

            let count = points.count
            func xPosition(for index: Int) -> CGFloat {
                guard count > 1 else { return size.width * 0.5 }
                return size.width * CGFloat(index) / CGFloat(count - 1)
            }

            // Neon Pink Heart Rate Trace
            var hrPath = Path()
            var hasStartedHR = false
            for (index, point) in points.enumerated() {
                guard let hrY = point.hrNormalizedY else { continue }
                let x = xPosition(for: index)
                let y = yPosition(for: CGFloat(hrY))
                if !hasStartedHR {
                    hrPath.move(to: CGPoint(x: x, y: y))
                    hasStartedHR = true
                } else {
                    hrPath.addLine(to: CGPoint(x: x, y: y))
                }
            }
            if hasStartedHR {
                context.stroke(
                    hrPath,
                    with: .color(WatchColor.heartRate.opacity(0.85)),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
            }

            // Electric Blue Pace Trace
            var pacePath = Path()
            for (index, point) in points.enumerated() {
                let x = xPosition(for: index)
                let y = yPosition(for: CGFloat(point.paceNormalizedY))
                if index == 0 {
                    pacePath.move(to: CGPoint(x: x, y: y))
                } else {
                    pacePath.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(
                pacePath,
                with: .color(WatchColor.pace),
                style: StrokeStyle(lineWidth: 3.0, lineCap: .round, lineJoin: .round)
            )
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Recent Lap Splits

    private var recentSplitsRow: some View {
        HStack(spacing: 4) {
            if let splits = summary?.recentLapSplits, !splits.isEmpty {
                ForEach(splits.suffix(4), id: \.lapNumber) { split in
                    splitChip(split: split)
                }
            } else {
                Text("Laps appear as completed")
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 5)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func splitChip(split: TrackLapSplit) -> some View {
        let tint = split.onTarget ? WatchColor.cadence : Color.secondary
        return HStack(spacing: 2) {
            Text("L\(split.lapNumber)")
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(split.splitFormatted)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
        .background(split.onTarget ? WatchColor.cadence.opacity(0.12) : Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(split.onTarget ? WatchColor.cadence.opacity(0.30) : Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}
