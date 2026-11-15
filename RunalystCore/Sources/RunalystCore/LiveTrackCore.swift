import Foundation

// MARK: - Live Activity Display Mode

/// Display presentation mode across Lock Screen Live Activities, Dynamic Island, and Watch pagers.
public enum LiveActivityDisplayMode: String, Sendable, Codable, Equatable, CaseIterable {
    case track
    case metrics
    case chart

    /// Next mode in the canonical 1 -> 2 -> 3 cycle.
    public var nextMode: LiveActivityDisplayMode {
        switch self {
        case .track: return .metrics
        case .metrics: return .chart
        case .chart: return .track
        }
    }

    /// User-facing descriptive title for view indicators and accessibility labels.
    public var title: String {
        switch self {
        case .track: return "Track"
        case .metrics: return "Metrics"
        case .chart: return "Chart"
        }
    }
}

// MARK: - Biometric Palette RGB

/// Deterministic, platform-agnostic RGB representation of Runalyst subconscious biometric colors.
public struct BiometricPaletteRGB: Sendable, Codable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

// MARK: - Live Track Snapshot

/// Pure, serializable snapshot of 400-meter stadium track kinematics and pacer status.
public struct LiveTrackSnapshot: Sendable, Codable, Equatable {
    /// 1-indexed lap count based on 400-meter completions.
    public let lapNumber: Int
    /// Meters completed along the current 400m lap (0...399).
    public let lapDistanceMeters: Int
    /// Normalized progress along the 400m oval (0.0..<1.0).
    public let lapProgress: Double
    /// Normalized target pacer progress along the 400m oval, or nil during calibration.
    public let ghostProgress: Double?
    /// Signed distance relative to target pacer in meters (positive = ahead, negative = behind).
    public let ghostDeltaMeters: Int?
    /// User-facing delta readout (e.g. "+12m ahead", "-8m behind", "On Pacer", or "Calibrating").
    public let ghostDeltaLabel: String
    /// Pre-formatted lap counter header (e.g. "Lap 3 • 240/400m").
    public let lapHeaderLabel: String
    /// Pre-formatted total cumulative distance respecting the athlete's unit preference.
    public let totalDistanceFormatted: String
    /// Pre-formatted elapsed duration within the current 400m lap (e.g. "1:24").
    public let lapElapsedFormatted: String
    /// Cadence-derived avatar stride frequency in Hz (0.0 when paused or idle).
    public let runnerStrideHz: Double
    /// Subconscious accent token driving status dots and glow rings.
    public let statusToken: PacingAccentToken
    /// Combined accessibility readout for VoiceOver.
    public let accessibilitySummary: String

    public init(
        lapNumber: Int, lapDistanceMeters: Int, lapProgress: Double,
        ghostProgress: Double?, ghostDeltaMeters: Int?, ghostDeltaLabel: String,
        lapHeaderLabel: String, totalDistanceFormatted: String, lapElapsedFormatted: String,
        runnerStrideHz: Double, statusToken: PacingAccentToken, accessibilitySummary: String
    ) {
        self.lapNumber = lapNumber
        self.lapDistanceMeters = lapDistanceMeters
        self.lapProgress = lapProgress
        self.ghostProgress = ghostProgress
        self.ghostDeltaMeters = ghostDeltaMeters
        self.ghostDeltaLabel = ghostDeltaLabel
        self.lapHeaderLabel = lapHeaderLabel
        self.totalDistanceFormatted = totalDistanceFormatted
        self.lapElapsedFormatted = lapElapsedFormatted
        self.runnerStrideHz = runnerStrideHz
        self.statusToken = statusToken
        self.accessibilitySummary = accessibilitySummary
    }
}

// MARK: - Live Trajectory Point & Summary

/// Pre-normalized coordinate point for the rolling trajectory chart.
public struct LiveTrajectoryPoint: Sendable, Codable, Equatable {
    public let elapsedSeconds: Int
    public let paceNormalizedY: Double
    public let hrNormalizedY: Double?

    public init(elapsedSeconds: Int, paceNormalizedY: Double, hrNormalizedY: Double? = nil) {
        self.elapsedSeconds = elapsedSeconds
        self.paceNormalizedY = paceNormalizedY
        self.hrNormalizedY = hrNormalizedY
    }
}

/// Recorded 400m lap completion split for tactical pacing debrief.
public struct TrackLapSplit: Sendable, Codable, Equatable {
    public let lapNumber: Int
    public let splitSeconds: Int
    public let splitFormatted: String
    public let onTarget: Bool

    public init(lapNumber: Int, splitSeconds: Int, splitFormatted: String, onTarget: Bool) {
        self.lapNumber = lapNumber
        self.splitSeconds = splitSeconds
        self.splitFormatted = splitFormatted
        self.onTarget = onTarget
    }
}

/// Bounded rolling 8-minute trajectory and recent lap split summary.
public struct LiveTrajectorySummary: Sendable, Codable, Equatable {
    public let points: [LiveTrajectoryPoint]
    public let corridorLowerY: Double
    public let corridorUpperY: Double
    public let recentLapSplits: [TrackLapSplit]
    public let windowLabel: String

    public init(
        points: [LiveTrajectoryPoint], corridorLowerY: Double,
        corridorUpperY: Double, recentLapSplits: [TrackLapSplit],
        windowLabel: String = "Last 8 min"
    ) {
        self.points = points
        self.corridorLowerY = corridorLowerY
        self.corridorUpperY = corridorUpperY
        self.recentLapSplits = recentLapSplits
        self.windowLabel = windowLabel
    }
}

// MARK: - LiveTrackCore Namespace

/// Mathematical projections, palettes, and pure calculators for stadium track kinematics.
public enum LiveTrackCore {

    /// Projects a normalized lap progress fraction into clockwise stadium oval coordinates.
    ///
    /// Progress 0.0 anchors at top-center (0.50, 0.08) and travels clockwise around the stadium track:
    /// - 0.000: Start / Finish Line at top-center (0.50, 0.08)
    /// - 0.250: Apex of right turn (0.92, 0.50)
    /// - 0.500: Opposite 200m mark at bottom-center (0.50, 0.92)
    /// - 0.750: Apex of left turn (0.08, 0.50)
    /// - 1.000: Completes lap at top-center (0.50, 0.08)
    public static func trackOvalPoint(progress: Double) -> (x: Double, y: Double) {
        let remainder = progress.truncatingRemainder(dividingBy: 1.0)
        let p = remainder < 0.0 ? remainder + 1.0 : remainder

        let topY = 0.08, bottomY = 0.92, centerY = 0.50
        let ry = (bottomY - topY) * 0.5 // 0.42
        let rx = 0.20, cxRight = 0.72, cxLeft = 0.28

        if p < 0.125 {
            // Segment 1: Top straightaway right half (x: 0.50 -> 0.72, y: 0.08)
            let fraction = p / 0.125
            return (0.50 + fraction * (cxRight - 0.50), topY)
        } else if p < 0.375 {
            // Segment 2: Right curve semicircle (angle: -pi/2 -> +pi/2)
            let fraction = (p - 0.125) / 0.250
            let angle = -Double.pi * 0.5 + fraction * Double.pi
            return (cxRight + rx * cos(angle), centerY + ry * sin(angle))
        } else if p < 0.625 {
            // Segment 3: Bottom straightaway (x: 0.72 -> 0.28, y: 0.92)
            let fraction = (p - 0.375) / 0.250
            return (cxRight - fraction * (cxRight - cxLeft), bottomY)
        } else if p < 0.875 {
            // Segment 4: Left curve semicircle (angle: +pi/2 -> +3*pi/2)
            let fraction = (p - 0.625) / 0.250
            let angle = Double.pi * 0.5 + fraction * Double.pi
            return (cxLeft + rx * cos(angle), centerY + ry * sin(angle))
        } else {
            // Segment 5: Top straightaway left half (x: 0.28 -> 0.50, y: 0.08)
            let fraction = min(1.0, (p - 0.875) / 0.125)
            return (cxLeft + fraction * (0.50 - cxLeft), topY)
        }
    }

    /// Resolves canonical RGB color components for every pacing accent token across all surfaces.
    public static func paletteRGB(for token: PacingAccentToken) -> BiometricPaletteRGB {
        switch token {
        case .electricBlue: return BiometricPaletteRGB(red: 0.04, green: 0.52, blue: 1.0)
        case .surgeBlue: return BiometricPaletteRGB(red: 0.12, green: 0.62, blue: 1.0)
        case .calibratingBlue: return BiometricPaletteRGB(red: 0.20, green: 0.60, blue: 1.0)
        case .surgeTeal: return BiometricPaletteRGB(red: 0.0, green: 0.90, blue: 0.75)
        case .vibrantGreen: return BiometricPaletteRGB(red: 0.20, green: 0.78, blue: 0.35)
        case .recoverAmber: return BiometricPaletteRGB(red: 1.0, green: 0.65, blue: 0.10)
        case .recoverOrange: return BiometricPaletteRGB(red: 1.0, green: 0.58, blue: 0.0)
        case .neonPink: return BiometricPaletteRGB(red: 1.0, green: 0.18, blue: 0.33)
        case .neutral: return BiometricPaletteRGB(red: 0.55, green: 0.55, blue: 0.58)
        }
    }
}

// MARK: - LiveTrackCalculator

/// Pure mathematical evaluations for 400-meter lap kinematics and pacer tracking.
public enum LiveTrackCalculator {

    /// Evaluates lap index, meters within lap, and normalized progress fraction.
    public static func lapKinematics(totalDistanceMeters: Double) -> (lapNumber: Int, lapDistanceMeters: Int, lapProgress: Double) {
        guard totalDistanceMeters > 0.0 else {
            return (lapNumber: 1, lapDistanceMeters: 0, lapProgress: 0.0)
        }
        let lapNum = Int(floor(totalDistanceMeters / 400.0)) + 1
        let remainder = totalDistanceMeters.truncatingRemainder(dividingBy: 400.0)
        let lapDist = Int(remainder.rounded(.down))
        let clampedDist = min(399, max(0, lapDist))
        let progress = min(0.9999, max(0.0, remainder / 400.0))
        return (lapNumber: lapNum, lapDistanceMeters: clampedDist, lapProgress: progress)
    }

    /// Evaluates ghost target pacer progress, meter lead/lag, and descriptive status label.
    public static func ghostKinematics(
        totalDistanceMeters: Double, elapsedSeconds: Int,
        targetPaceSecondsPerKm: Int?, isCalibrating: Bool
    ) -> (ghostProgress: Double?, ghostDeltaMeters: Int?, ghostDeltaLabel: String) {
        if isCalibrating {
            return (ghostProgress: nil, ghostDeltaMeters: nil, ghostDeltaLabel: "Calibrating")
        }
        guard let targetPace = targetPaceSecondsPerKm, targetPace > 0 else {
            return (ghostProgress: nil, ghostDeltaMeters: nil, ghostDeltaLabel: "--")
        }
        let targetPacePerMeter = Double(targetPace) / 1000.0
        let ghostTotalDist = Double(elapsedSeconds) / targetPacePerMeter
        let remainder = ghostTotalDist.truncatingRemainder(dividingBy: 400.0)
        let normalizedRemainder = remainder < 0.0 ? remainder + 400.0 : remainder
        let progress = min(0.9999, max(0.0, normalizedRemainder / 400.0))

        let delta = Int((totalDistanceMeters - ghostTotalDist).rounded())
        let label: String
        if delta > 0 {
            label = "+\(delta)m ahead"
        } else if delta < 0 {
            label = "\(delta)m behind"
        } else {
            label = "On Pacer"
        }
        return (ghostProgress: progress, ghostDeltaMeters: delta, ghostDeltaLabel: label)
    }

    /// Calculates avatar animation stride frequency in Hz clamped to [1.5, 4.0], or 0.0 when paused.
    public static func strideFrequencyHz(cadenceSPM: Int?, isPaused: Bool) -> Double {
        guard !isPaused, let cadence = cadenceSPM, cadence > 0 else {
            return 0.0
        }
        let rawHz = Double(cadence) / 60.0
        return min(4.0, max(1.5, rawHz))
    }

    /// Formats cumulative distance in metric ("2.24 km") or imperial ("1.00 mi").
    public static func formatTotalDistance(meters: Double, useMetricSystem: Bool) -> String {
        let validMeters = max(0.0, meters)
        if useMetricSystem {
            let km = validMeters / 1000.0
            return String(format: "%.2f km", km)
        } else {
            let miles = validMeters / 1609.344
            return String(format: "%.2f mi", miles)
        }
    }

    /// Formats seconds into mm:ss.
    public static func formatDuration(seconds: Int) -> String {
        let validSecs = max(0, seconds)
        let mins = validSecs / 60
        let remSecs = validSecs % 60
        return String(format: "%d:%02d", mins, remSecs)
    }

    /// Formats combined accessibility string for VoiceOver.
    public static func buildAccessibilitySummary(
        lapHeaderLabel: String, totalDistanceFormatted: String,
        lapElapsedFormatted: String, ghostDeltaLabel: String, isPaused: Bool
    ) -> String {
        if isPaused {
            return "Paused. \(lapHeaderLabel), \(totalDistanceFormatted) total."
        }
        var parts = ["\(lapHeaderLabel)", "\(totalDistanceFormatted) total", "lap time \(lapElapsedFormatted)"]
        if !ghostDeltaLabel.isEmpty && ghostDeltaLabel != "--" {
            parts.append(ghostDeltaLabel)
        }
        return parts.joined(separator: ", ") + "."
    }

    /// Assembles a complete LiveTrackSnapshot from pure telemetry inputs.
    public static func calculateSnapshot(
        totalDistanceMeters: Double, elapsedSeconds: Int, lapElapsedSeconds: Int,
        cadenceSPM: Int?, targetPaceSecondsPerKm: Int?, isCalibrating: Bool,
        isPaused: Bool, statusToken: PacingAccentToken, useMetricSystem: Bool
    ) -> LiveTrackSnapshot {
        let (lapNum, lapDist, lapProg) = lapKinematics(totalDistanceMeters: totalDistanceMeters)
        let (ghostProg, ghostDelta, ghostLabel) = ghostKinematics(
            totalDistanceMeters: totalDistanceMeters,
            elapsedSeconds: elapsedSeconds,
            targetPaceSecondsPerKm: targetPaceSecondsPerKm,
            isCalibrating: isCalibrating
        )
        let strideHz = strideFrequencyHz(cadenceSPM: cadenceSPM, isPaused: isPaused)
        let distFormatted = formatTotalDistance(meters: totalDistanceMeters, useMetricSystem: useMetricSystem)
        let lapElapsedFormatted = formatDuration(seconds: lapElapsedSeconds)
        let headerLabel = "Lap \(lapNum) • \(lapDist)/400m"
        let summary = buildAccessibilitySummary(
            lapHeaderLabel: headerLabel, totalDistanceFormatted: distFormatted,
            lapElapsedFormatted: lapElapsedFormatted, ghostDeltaLabel: ghostLabel,
            isPaused: isPaused
        )

        return LiveTrackSnapshot(
            lapNumber: lapNum, lapDistanceMeters: lapDist, lapProgress: lapProg,
            ghostProgress: ghostProg, ghostDeltaMeters: ghostDelta, ghostDeltaLabel: ghostLabel,
            lapHeaderLabel: headerLabel, totalDistanceFormatted: distFormatted,
            lapElapsedFormatted: lapElapsedFormatted, runnerStrideHz: strideHz,
            statusToken: statusToken, accessibilitySummary: summary
        )
    }
}

// MARK: - LiveTrackAccumulator

/// Pure, deterministic accumulator managing rolling trajectory samples and 400m lap splits.
public struct LiveTrackAccumulator: Sendable, Equatable {

    /// Telemetry point recorded at an elapsed duration.
    public struct RawSample: Sendable, Equatable {
        public let elapsedSeconds: Int
        public let distanceMeters: Double
        public let paceSecondsPerKm: Int?
        public let heartRateBPM: Int?
        public let cadenceSPM: Int?

        public init(
            elapsedSeconds: Int, distanceMeters: Double,
            paceSecondsPerKm: Int?, heartRateBPM: Int?, cadenceSPM: Int?
        ) {
            self.elapsedSeconds = elapsedSeconds
            self.distanceMeters = distanceMeters
            self.paceSecondsPerKm = paceSecondsPerKm
            self.heartRateBPM = heartRateBPM
            self.cadenceSPM = cadenceSPM
        }
    }

    private(set) public var rawSamples: [RawSample]
    private(set) public var completedLapSplits: [TrackLapSplit]
    private(set) public var lastRecordedDistanceMeters: Double
    private(set) public var currentLapStartElapsedSeconds: Int

    public init(
        rawSamples: [RawSample] = [],
        completedLapSplits: [TrackLapSplit] = [],
        lastRecordedDistanceMeters: Double = 0.0,
        currentLapStartElapsedSeconds: Int = 0
    ) {
        self.rawSamples = rawSamples
        self.completedLapSplits = completedLapSplits
        self.lastRecordedDistanceMeters = lastRecordedDistanceMeters
        self.currentLapStartElapsedSeconds = currentLapStartElapsedSeconds
    }

    /// Records a new telemetry sample, prunes samples older than 480 seconds, and tracks 400m lap splits.
    public mutating func recordSample(
        elapsedSeconds: Int, distanceMeters: Double,
        paceSecondsPerKm: Int?, heartRateBPM: Int?, cadenceSPM: Int?,
        targetPaceSecondsPerKm: Int? = nil
    ) {
        let cutoff = elapsedSeconds - 480
        rawSamples.removeAll { $0.elapsedSeconds < cutoff }

        let sample = RawSample(
            elapsedSeconds: elapsedSeconds, distanceMeters: distanceMeters,
            paceSecondsPerKm: paceSecondsPerKm, heartRateBPM: heartRateBPM, cadenceSPM: cadenceSPM
        )
        rawSamples.append(sample)

        if distanceMeters > 0.0 && lastRecordedDistanceMeters >= 0.0 {
            let oldLap = Int(floor(lastRecordedDistanceMeters / 400.0))
            let newLap = Int(floor(distanceMeters / 400.0))
            if newLap > oldLap {
                for completedLapIndex in (oldLap + 1)...newLap {
                    let lapNumber = completedLapIndex
                    let splitSecs = max(1, elapsedSeconds - currentLapStartElapsedSeconds)
                    let formatted = LiveTrackCalculator.formatDuration(seconds: splitSecs)

                    let onTarget: Bool
                    if let target = targetPaceSecondsPerKm, target > 0 {
                        let targetLapSeconds = Double(target) * 0.400
                        let tolerance = max(6.0, targetLapSeconds * 0.08)
                        onTarget = abs(Double(splitSecs) - targetLapSeconds) <= tolerance
                    } else {
                        onTarget = true
                    }

                    let split = TrackLapSplit(
                        lapNumber: lapNumber, splitSeconds: splitSecs,
                        splitFormatted: formatted, onTarget: onTarget
                    )
                    completedLapSplits.append(split)
                    currentLapStartElapsedSeconds = elapsedSeconds
                }
                if completedLapSplits.count > 4 {
                    completedLapSplits = Array(completedLapSplits.suffix(4))
                }
            }
        }
        lastRecordedDistanceMeters = distanceMeters
    }

    /// Produces a LiveTrackSnapshot reflecting current telemetry and accumulator state.
    public func makeTrackSnapshot(
        totalDistanceMeters: Double, elapsedSeconds: Int, cadenceSPM: Int?,
        targetPaceSecondsPerKm: Int?, isCalibrating: Bool, isPaused: Bool,
        statusToken: PacingAccentToken, useMetricSystem: Bool
    ) -> LiveTrackSnapshot {
        let lapElapsed = max(0, elapsedSeconds - currentLapStartElapsedSeconds)
        return LiveTrackCalculator.calculateSnapshot(
            totalDistanceMeters: totalDistanceMeters,
            elapsedSeconds: elapsedSeconds,
            lapElapsedSeconds: lapElapsed,
            cadenceSPM: cadenceSPM,
            targetPaceSecondsPerKm: targetPaceSecondsPerKm,
            isCalibrating: isCalibrating,
            isPaused: isPaused,
            statusToken: statusToken,
            useMetricSystem: useMetricSystem
        )
    }

    /// Emits a downsampled LiveTrajectorySummary over the rolling 480-second window.
    public func makeTrajectorySummary(targetPaceSecondsPerKm: Int?) -> LiveTrajectorySummary {
        let (corridorLower, corridorUpper): (Double, Double) = {
            guard let target = targetPaceSecondsPerKm, target > 0 else {
                return (0.42, 0.58)
            }
            let halfSpan = Double(target) * 0.25
            let tolerance = max(5.0, Double(target) * 0.05)
            let offset = min(0.40, tolerance / (halfSpan * 2.0))
            return (0.50 - offset, 0.50 + offset)
        }()

        let downsampledSamples: [RawSample] = {
            guard rawSamples.count > 24 else { return rawSamples }
            let total = rawSamples.count
            return (0..<24).map { i in
                let index = Int(round(Double(i) * Double(total - 1) / 23.0))
                return rawSamples[index]
            }
        }()

        let points: [LiveTrajectoryPoint] = downsampledSamples.map { sample in
            let paceY: Double = {
                guard let pace = sample.paceSecondsPerKm, pace > 0 else { return 0.50 }
                if let target = targetPaceSecondsPerKm, target > 0 {
                    let halfSpan = Double(target) * 0.25
                    let delta = Double(target - pace)
                    let norm = 0.50 + (delta / (halfSpan * 2.0))
                    return min(1.0, max(0.0, norm))
                } else {
                    let norm = 1.0 - (Double(pace - 180) / 300.0)
                    return min(1.0, max(0.0, norm))
                }
            }()

            let hrY: Double? = {
                guard let hr = sample.heartRateBPM, hr > 0 else { return nil }
                let norm = Double(hr - 100) / 100.0
                return min(1.0, max(0.0, norm))
            }()

            return LiveTrajectoryPoint(
                elapsedSeconds: sample.elapsedSeconds,
                paceNormalizedY: paceY,
                hrNormalizedY: hrY
            )
        }

        return LiveTrajectorySummary(
            points: points,
            corridorLowerY: corridorLower,
            corridorUpperY: corridorUpper,
            recentLapSplits: completedLapSplits,
            windowLabel: "Last 8 min"
        )
    }
}
