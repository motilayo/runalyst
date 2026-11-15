import ActivityKit
import RunalystCore
import SwiftUI
import WidgetKit

// MARK: - Lock Screen View 1: 3D 400m Stadium Track

/// Lock Screen View 1: Crisp flat 2D 400m oval with runner avatar, ghost pacer, and lap kinematics at true proportions.
public struct LiveActivityTrackView: View {
    public let snapshot: WatchLiveRunSnapshot

    public init(snapshot: WatchLiveRunSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Side-by-side Stadium Track & Lap Kinematics
            HStack(alignment: .center, spacing: 12) {
                // Left: 2D Flat Track Oval at True Proportions (132x48)
                GeometryReader { geometry in
                    let width = max(0, geometry.size.width - 20)
                    let height = max(0, geometry.size.height - 12)

                    ZStack {
                        // Track surface fill
                        TrackOvalShape()
                            .fill(Color.white.opacity(0.04))

                        // Track lane boundary
                        TrackOvalShape()
                            .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 3, lineCap: .round))

                        // Start / Finish Line tick at top-center (0.50, 0.08)
                        Rectangle()
                            .fill(Color.white.opacity(0.70))
                            .frame(width: 2, height: 10)
                            .position(x: width * 0.50, y: height * 0.08)

                        // Muted ghost pacer dot (omitted when calibrating or absent)
                        if snapshot.phase != .calibrating, let ghostProg = snapshot.trackSnapshot?.ghostProgress {
                            let ghostPoint = LiveTrackCore.trackOvalPoint(progress: ghostProg)
                            Circle()
                                .fill(Color.white.opacity(0.45))
                                .frame(width: 8, height: 8)
                                .position(x: ghostPoint.x * width, y: ghostPoint.y * height)
                        }

                        // Runner avatar positioned along the flat 2D oval
                        RunnerTrackAvatarView(
                            progress: snapshot.trackSnapshot?.lapProgress ?? 0.0,
                            statusToken: snapshot.trackSnapshot?.statusToken ?? snapshot.biometricStatusToken,
                            isPaused: snapshot.isPaused
                        )
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .frame(width: 132, height: 48)

                // Right: Lap Header, Calibration / Ghost Delta, Active Block
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.trackSnapshot?.lapHeaderLabel ?? "Lap 1 • 0/400m")
                        .font(.system(.subheadline, design: .rounded).bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if snapshot.phase == .calibrating {
                        if let calProg = snapshot.calibrationProgress {
                            ProgressView(value: min(max(calProg, 0.0), 1.0))
                                .tint(Color(token: .calibratingBlue))
                        } else {
                            Text("Calibrating")
                                .font(.system(.caption2, design: .rounded).bold())
                                .foregroundStyle(Color(token: .calibratingBlue))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    } else if let deltaLabel = snapshot.trackSnapshot?.ghostDeltaLabel, !deltaLabel.isEmpty {
                        Text(deltaLabel)
                            .font(.system(.caption2, design: .rounded).bold())
                            .foregroundStyle(Color(token: snapshot.trackSnapshot?.statusToken ?? snapshot.biometricStatusToken))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    if let badge = snapshot.activeBlockBadge {
                        HStack(spacing: 6) {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(token: snapshot.biometricStatusToken).opacity(0.20))
                                .foregroundStyle(Color(token: snapshot.biometricStatusToken))
                                .clipShape(Capsule())

                            if let remaining = snapshot.activeBlockRemainingFormatted {
                                Text(remaining)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Sub-bar: Pace, Cadence, HR readouts
            HStack {
                Text(snapshot.filteredPaceFormatted)
                    .font(.system(.caption, design: .rounded).bold().monospacedDigit())
                    .foregroundStyle(Color(token: .electricBlue))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Text(snapshot.filteredCadenceFormatted)
                    .font(.system(.caption, design: .rounded).bold().monospacedDigit())
                    .foregroundStyle(Color(token: .vibrantGreen))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Text(snapshot.filteredHeartRateFormatted)
                    .font(.system(.caption, design: .rounded).bold().monospacedDigit())
                    .foregroundStyle(Color(token: .neonPink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(snapshot.trackSnapshot?.accessibilitySummary ?? "\(snapshot.headerTitle), \(snapshot.biometricStatusLabel)")
    }
}

// MARK: - Lock Screen View 2: Sweaty Hands Metrics Grid & Pace Gauge

/// Lock Screen View 2: High-contrast 2x2 monospaced telemetry grid + linear dynamic pace gauge.
public struct LiveActivityMetricsView: View {
    public let snapshot: WatchLiveRunSnapshot

    public init(snapshot: WatchLiveRunSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Active block / refractory countdown badge (omitted when nil to preserve height budget)
            if let badge = snapshot.activeBlockBadge {
                HStack(spacing: 6) {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color(token: snapshot.biometricStatusToken).opacity(0.20))
                        .foregroundStyle(Color(token: snapshot.biometricStatusToken))
                        .clipShape(Capsule())

                    if let remaining = snapshot.activeBlockRemainingFormatted {
                        Text(remaining)
                            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !snapshot.deviationTitle.isEmpty {
                        Text(snapshot.deviationTitle)
                            .font(.system(.caption2, design: .rounded).bold())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }

            // 2x2 Telemetry Grid
            Grid(horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    // Pace + Target
                    VStack(alignment: .leading, spacing: 1) {
                        Text("PACE")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(snapshot.filteredPaceFormatted)
                                .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color(token: .electricBlue))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if !snapshot.targetPaceFormatted.isEmpty && snapshot.targetPaceFormatted != "--" {
                                Text("/ \(snapshot.targetPaceFormatted)")
                                    .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Cadence
                    VStack(alignment: .leading, spacing: 1) {
                        Text("CADENCE")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(snapshot.filteredCadenceFormatted)
                            .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color(token: .vibrantGreen))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GridRow {
                    // Heart Rate
                    VStack(alignment: .leading, spacing: 1) {
                        Text("HEART RATE")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(snapshot.filteredHeartRateFormatted)
                            .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color(token: .neonPink))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Lap Progress or Biometric Status
                    VStack(alignment: .leading, spacing: 1) {
                        Text(snapshot.trackSnapshot != nil ? "LAP" : "STATUS")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(snapshot.trackSnapshot?.lapHeaderLabel ?? snapshot.biometricStatusLabel)
                            .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Dynamic Pace Gauge Target Band
            GeometryReader { geometry in
                let width = geometry.size.width
                let lower = min(max(snapshot.targetBandLowerNormalized, 0.0), 1.0)
                let upper = min(max(snapshot.targetBandUpperNormalized, lower), 1.0)
                let needle = min(max(snapshot.paceGaugeNormalizedPosition, 0.0), 1.0)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 5)

                    // Target pace green band
                    Capsule()
                        .fill(Color(token: .vibrantGreen).opacity(0.50))
                        .frame(width: max(4, (upper - lower) * width), height: 5)
                        .offset(x: lower * width)

                    // Current pace needle
                    Circle()
                        .fill(Color(token: .electricBlue))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .offset(x: max(0, min(width - 10, needle * width - 5)))
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Pace \(snapshot.filteredPaceFormatted), target \(snapshot.targetPaceFormatted), " +
            "Cadence \(snapshot.filteredCadenceFormatted), Heart Rate \(snapshot.filteredHeartRateFormatted)"
        )
    }
}

// MARK: - Lock Screen View 3: Rolling Trajectory Chart & Lap Splits

/// Lock Screen View 3: Rolling 8-minute pace corridor + HR trajectory canvas with recent 400m lap splits.
public struct LiveActivityChartView: View {
    public let snapshot: WatchLiveRunSnapshot

    public init(snapshot: WatchLiveRunSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Chart Header & Micro Legend
            HStack {
                Text(snapshot.trajectorySummary?.windowLabel ?? "Last 8 min")
                    .font(.system(.caption2, design: .rounded).bold())
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    legendItem(title: "Pace", color: Color(token: .electricBlue))
                    legendItem(title: "HR", color: Color(token: .neonPink))
                    legendItem(title: "Target", color: Color(token: .vibrantGreen).opacity(0.60))
                }
            }

            // Trajectory Canvas
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let usableHeight = max(1.0, height - 8.0)
                let points = snapshot.trajectorySummary?.points ?? []
                let corridorLower = snapshot.trajectorySummary?.corridorLowerY ?? 0.42
                let corridorUpper = snapshot.trajectorySummary?.corridorUpperY ?? 0.58

                ZStack(alignment: .topLeading) {
                    // Target Pace Corridor Band (y = 4 + usableHeight * (1.0 - clampedY))
                    let clampedUpper = min(1.0, max(0.0, corridorUpper))
                    let clampedLower = min(1.0, max(0.0, corridorLower))
                    let corridorTop = 4.0 + usableHeight * (1.0 - clampedUpper)
                    let corridorBottom = 4.0 + usableHeight * (1.0 - clampedLower)
                    let corridorHeight = max(2.0, corridorBottom - corridorTop)

                    Rectangle()
                        .fill(Color(token: .vibrantGreen).opacity(0.18))
                        .frame(width: width, height: corridorHeight)
                        .offset(y: corridorTop)

                    // Baseline guideline at 50%
                    let baselineY = 4.0 + usableHeight * 0.50
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: baselineY))
                        path.addLine(to: CGPoint(x: width, y: baselineY))
                    }
                    .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    if points.count > 1 {
                        // Electric Blue Pace Line
                        Path { path in
                            for (index, point) in points.enumerated() {
                                let coordX = CGFloat(index) / CGFloat(points.count - 1) * width
                                let clampedY = min(1.0, max(0.0, point.paceNormalizedY))
                                let coordY = 4.0 + usableHeight * (1.0 - clampedY)
                                if index == 0 {
                                    path.move(to: CGPoint(x: coordX, y: coordY))
                                } else {
                                    path.addLine(to: CGPoint(x: coordX, y: coordY))
                                }
                            }
                        }
                        .stroke(Color(token: .electricBlue), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        // Neon Pink HR Line
                        Path { path in
                            var hasStarted = false
                            for (index, point) in points.enumerated() {
                                guard let hrNorm = point.hrNormalizedY else { continue }
                                let coordX = CGFloat(index) / CGFloat(points.count - 1) * width
                                let clampedY = min(1.0, max(0.0, hrNorm))
                                let coordY = 4.0 + usableHeight * (1.0 - clampedY)
                                if !hasStarted {
                                    path.move(to: CGPoint(x: coordX, y: coordY))
                                    hasStarted = true
                                } else {
                                    path.addLine(to: CGPoint(x: coordX, y: coordY))
                                }
                            }
                        }
                        .stroke(Color(token: .neonPink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    } else {
                        // Empty state placeholder
                        Text("Buffering trajectory telemetry...")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }
            }
            .frame(height: 38)

            // Recent Lap Splits Chips (up to 4)
            let splits = snapshot.trajectorySummary?.recentLapSplits ?? []
            if !splits.isEmpty {
                HStack(spacing: 6) {
                    ForEach(splits, id: \.lapNumber) { split in
                        HStack(spacing: 3) {
                            Text("L\(split.lapNumber)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(split.splitFormatted)
                                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(split.onTarget ? Color(token: .vibrantGreen) : Color(token: .neonPink))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rolling trajectory chart for \(snapshot.trajectorySummary?.windowLabel ?? "Last 8 min")")
    }

    private func legendItem(title: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}
