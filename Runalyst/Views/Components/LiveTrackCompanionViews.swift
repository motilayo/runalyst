import RunalystCore
import SwiftUI

// MARK: - Stadium Track Shape

/// Continuous 400m stadium track oval shape conforming to `LiveTrackCore.trackOvalPoint`.
public struct StadiumTrackShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 100
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let point = LiveTrackCore.trackOvalPoint(progress: progress)
            let cgPoint = CGPoint(x: point.x * rect.width, y: point.y * rect.height)
            if step == 0 {
                path.move(to: cgPoint)
            } else {
                path.addLine(to: cgPoint)
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Companion Track Page View

/// Hollow 3D 400m stadium track view with cadence-synced animated avatar and ghost pacer.
public struct CompanionTrackPageView: View {
    public let snapshot: WatchLiveRunSnapshot

    public init(snapshot: WatchLiveRunSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        let track = snapshot.trackSnapshot
        let lapProgress = track?.lapProgress ?? 0.0
        let strideHz = track?.runnerStrideHz ?? 0.0

        VStack(spacing: 8) {
            // Lap Header & Delta Status Row
            HStack {
                Text(track?.lapHeaderLabel ?? "Lap 1 • 0/400m")
                    .font(.system(.subheadline, design: .rounded).bold())
                    .monospacedDigit()
                    .foregroundColor(.primary)

                if let total = track?.totalDistanceFormatted, !total.isEmpty {
                    Text("(\(total))")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(track?.ghostDeltaLabel ?? (snapshot.deviationTitle.isEmpty ? "On Pacer" : snapshot.deviationTitle))
                    .font(.system(.caption, design: .rounded).bold())
                    .foregroundColor(
                        snapshot.phase == .calibrating
                            ? Color(token: .calibratingBlue)
                            : Color(token: snapshot.biometricStatusToken)
                    )
            }

            // Calibration Progress Bar (during baseline phase)
            if snapshot.phase == .calibrating, let progress = snapshot.calibrationProgress {
                VStack(spacing: 3) {
                    ProgressView(value: min(1.0, max(0.0, progress)))
                        .tint(Color(token: .calibratingBlue))
                    HStack {
                        Text("Calibrating 400m Baseline...")
                            .font(.system(.caption2, design: .rounded).bold())
                            .foregroundColor(Color(token: .calibratingBlue))
                        Spacer()
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(.system(.caption2, design: .rounded).bold())
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
            } else if let badge = snapshot.activeBlockBadge {
                // Adaptive Micro-Block Badge
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                    Text(badge)
                        .font(.system(.caption2, design: .rounded).bold())
                    if let rem = snapshot.activeBlockRemainingFormatted {
                        Text("• \(rem)")
                            .font(.system(.caption2, design: .rounded))
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(token: .surgeTeal).opacity(0.18))
                .foregroundColor(Color(token: .surgeTeal))
                .clipShape(Capsule())
            }

            // 3D Stadium Track Canvas
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height

                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: (track?.runnerStrideHz ?? 0) <= 0)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let isRunning = strideHz > 0.0 && snapshot.phase != .paused
                    let bob = isRunning ? CGFloat(sin(time * strideHz * 2.0 * .pi * 2.0)) * 2.5 : 0.0

                    ZStack {
                        // Track lane base
                        StadiumTrackShape()
                            .stroke(Color(UIColor.tertiarySystemFill), lineWidth: 14)

                        // Centerline dashed marker
                        StadiumTrackShape()
                            .stroke(
                                Color.primary.opacity(0.18),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                            )

                        // Start / Finish Line at top-center (0.50, 0.08)
                        Path { path in
                            let fx = 0.50 * width
                            let fy = 0.08 * height
                            path.move(to: CGPoint(x: fx, y: fy - 7))
                            path.addLine(to: CGPoint(x: fx, y: fy + 7))
                        }
                        .stroke(Color.white.opacity(0.9), lineWidth: 2)

                        // Muted Ghost Pacer Dot (omitted when calibrating)
                        if snapshot.phase != .calibrating, let ghostProgress = track?.ghostProgress {
                            let ghostPt = LiveTrackCore.trackOvalPoint(progress: ghostProgress)
                            Circle()
                                .fill(Color.white.opacity(0.65))
                                .frame(width: 8, height: 8)
                                .overlay(Circle().stroke(Color.secondary.opacity(0.8), lineWidth: 1.5))
                                .position(x: ghostPt.x * width, y: ghostPt.y * height)
                        }

                        // Cadence-synced Runner Avatar
                        let runnerPt = LiveTrackCore.trackOvalPoint(progress: lapProgress)
                        ZStack {
                            Circle()
                                .fill(Color(token: snapshot.biometricStatusToken))
                                .frame(width: 22, height: 22)
                                .shadow(color: Color(token: snapshot.biometricStatusToken).opacity(0.6), radius: 4)
                            Image(systemName: "figure.run")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .position(x: runnerPt.x * width, y: runnerPt.y * height + bob)
                    }
                    .rotation3DEffect(.degrees(26), axis: (x: 1, y: 0, z: 0), perspective: 0.25)
                }
            }
            .frame(height: 115)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(track?.accessibilitySummary ?? "\(snapshot.headerTitle), \(snapshot.stateTitle)")
    }
}

// MARK: - Companion Metrics Page View

/// Hollow 2x2 monospaced metrics grid paired with dynamic pace gauge bar.
public struct CompanionMetricsPageView: View {
    public let snapshot: WatchLiveRunSnapshot

    public init(snapshot: WatchLiveRunSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(spacing: 10) {
            // Target Pace Normalized Corridor Bar Gauge
            dynamicPaceGauge(snapshot: snapshot)

            // 2x2 Monospaced Grid
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    metricGridTile(
                        title: "PACE",
                        primaryValue: snapshot.filteredPaceFormatted,
                        primaryColor: Color(token: .electricBlue),
                        secondaryText: "Target: \(snapshot.targetPaceFormatted)"
                    )
                    metricGridTile(
                        title: "CADENCE",
                        primaryValue: snapshot.filteredCadenceFormatted,
                        primaryColor: Color(token: .vibrantGreen),
                        secondaryText: "Nominal"
                    )
                }

                HStack(spacing: 10) {
                    metricGridTile(
                        title: "HEART RATE",
                        primaryValue: snapshot.filteredHeartRateFormatted,
                        primaryColor: Color(token: .neonPink),
                        secondaryText: "Nominal"
                    )
                    metricGridTile(
                        title: "LAP / ELAPSED",
                        primaryValue: snapshot.trackSnapshot?.lapElapsedFormatted ?? snapshot.elapsedTimeFormatted,
                        primaryColor: .primary,
                        secondaryText: "Total: \(snapshot.elapsedTimeFormatted)"
                    )
                }
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Pace \(snapshot.filteredPaceFormatted), Target \(snapshot.targetPaceFormatted), " +
            "Cadence \(snapshot.filteredCadenceFormatted), Heart Rate \(snapshot.filteredHeartRateFormatted), " +
            "Elapsed \(snapshot.elapsedTimeFormatted)"
        )
    }

    private func metricGridTile(
        title: String,
        primaryValue: String,
        primaryColor: Color,
        secondaryText: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.caption2, design: .rounded).bold())
                .foregroundColor(.secondary)
            Text(primaryValue)
                .font(.system(.headline, design: .rounded).bold())
                .monospacedDigit()
                .foregroundColor(primaryColor)
            if let secondaryText, !secondaryText.isEmpty {
                Text(secondaryText)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Text(" ")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.clear)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(UIColor.tertiarySystemFill).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func dynamicPaceGauge(snapshot: WatchLiveRunSnapshot) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let lower = min(max(snapshot.targetBandLowerNormalized, 0.0), 1.0)
            let upper = min(max(snapshot.targetBandUpperNormalized, lower), 1.0)
            let needle = min(max(snapshot.paceGaugeNormalizedPosition, 0.0), 1.0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(UIColor.tertiarySystemFill))
                    .frame(height: 8)

                Capsule()
                    .fill(Color(token: .vibrantGreen).opacity(0.45))
                    .frame(width: max(4, (upper - lower) * width), height: 8)
                    .offset(x: lower * width)

                Circle()
                    .fill(Color(token: .electricBlue))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: max(0, min(width - 14, needle * width - 7)))
            }
        }
        .frame(height: 14)
    }
}

// MARK: - Companion Chart Page View

/// Hollow rolling 8-minute pace corridor and trajectory chart with recent lap splits.
public struct CompanionChartPageView: View {
    public let snapshot: WatchLiveRunSnapshot

    public init(snapshot: WatchLiveRunSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header & Legend Row
            HStack(spacing: 8) {
                Text(snapshot.trajectorySummary?.windowLabel ?? "Last 8 min")
                    .font(.system(.caption2, design: .rounded).bold())
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    Circle().fill(Color(token: .electricBlue)).frame(width: 6, height: 6)
                    Text("Pace").font(.system(.caption2, design: .rounded)).foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(token: .vibrantGreen).opacity(0.45))
                        .frame(width: 10, height: 5)
                    Text("Target").font(.system(.caption2, design: .rounded)).foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Circle().fill(Color(token: .neonPink)).frame(width: 6, height: 6)
                    Text("HR").font(.system(.caption2, design: .rounded)).foregroundColor(.secondary)
                }
            }

            // Rolling Pace & HR Canvas
            Canvas { context, size in
                guard size.width > 0, size.height > 0 else { return }

                let insetY: CGFloat = 4.0
                let usableHeight = max(1.0, size.height - (insetY * 2.0))
                func yPosition(for normalizedY: Double) -> CGFloat {
                    insetY + (1.0 - CGFloat(min(max(normalizedY, 0.0), 1.0))) * usableHeight
                }

                // 1. Shaded Target Corridor
                let lowerY = snapshot.trajectorySummary?.corridorLowerY ?? 0.42
                let upperY = snapshot.trajectorySummary?.corridorUpperY ?? 0.58
                let topY = yPosition(for: upperY)
                let bottomY = yPosition(for: lowerY)
                let bandHeight = max(2.0, bottomY - topY)
                let corridorRect = CGRect(x: 0, y: topY, width: size.width, height: bandHeight)
                context.fill(Path(corridorRect), with: .color(Color(token: .vibrantGreen).opacity(0.18)))

                var centerLine = Path()
                let centerY = (topY + bottomY) * 0.5
                centerLine.move(to: CGPoint(x: 0, y: centerY))
                centerLine.addLine(to: CGPoint(x: size.width, y: centerY))
                context.stroke(
                    centerLine,
                    with: .color(Color(token: .vibrantGreen).opacity(0.35)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )

                // 2. Pace & HR Polylines
                if let summary = snapshot.trajectorySummary, !summary.points.isEmpty {
                    let points = summary.points
                    let count = points.count

                    // Pace Polyline (Electric Blue)
                    var pacePath = Path()
                    for (index, pt) in points.enumerated() {
                        let x = count > 1 ? (Double(index) / Double(count - 1)) * size.width : size.width * 0.5
                        let y = yPosition(for: pt.paceNormalizedY)
                        let point = CGPoint(x: x, y: y)
                        if index == 0 {
                            pacePath.move(to: point)
                        } else {
                            pacePath.addLine(to: point)
                        }
                    }
                    context.stroke(
                        pacePath,
                        with: .color(Color(token: .electricBlue)),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                    )

                    // HR Polyline (Neon Pink)
                    var hrPath = Path()
                    var hasHR = false
                    for (index, pt) in points.enumerated() {
                        guard let hrNorm = pt.hrNormalizedY else { continue }
                        let x = count > 1 ? (Double(index) / Double(count - 1)) * size.width : size.width * 0.5
                        let y = yPosition(for: hrNorm)
                        let point = CGPoint(x: x, y: y)
                        if !hasHR {
                            hrPath.move(to: point)
                            hasHR = true
                        } else {
                            hrPath.addLine(to: point)
                        }
                    }
                    if hasHR {
                        context.stroke(
                            hrPath,
                            with: .color(Color(token: .neonPink)),
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
            }
            .frame(height: 100)
            .background(Color(UIColor.tertiarySystemFill).opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Recent 400m Lap Split Chips (up to 4)
            let splits = Array((snapshot.trajectorySummary?.recentLapSplits ?? []).suffix(4))
            if !splits.isEmpty {
                HStack(spacing: 6) {
                    ForEach(splits, id: \.lapNumber) { split in
                        HStack(spacing: 3) {
                            Text("L\(split.lapNumber)")
                                .font(.system(.caption2, design: .rounded).bold())
                                .foregroundColor(.secondary)
                            Text(split.splitFormatted)
                                .font(.system(.caption2, design: .rounded).bold())
                                .monospacedDigit()
                                .foregroundColor(
                                    split.onTarget
                                        ? Color(token: .vibrantGreen)
                                        : Color(token: .recoverOrange)
                                )
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(UIColor.tertiarySystemFill))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    split.onTarget
                                        ? Color(token: .vibrantGreen).opacity(0.4)
                                        : Color(token: .recoverOrange).opacity(0.4),
                                    lineWidth: 1
                                )
                        )
                    }
                    Spacer()
                }
            } else {
                Text("Lap splits record at 400m intervals")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Rolling trajectory chart over \(snapshot.trajectorySummary?.windowLabel ?? "last 8 minutes")."
        )
    }
}
