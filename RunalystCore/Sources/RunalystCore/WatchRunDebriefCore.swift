import Foundation

// MARK: - Post-Run Debrief Model

/// Pure sports science post-run debrief summary for on-wrist review.
public struct WatchRunDebrief: Sendable, Equatable, Codable {
    /// Bullet 1: Pace adaptations, surges, and recovery adjustments.
    public let adaptationsBullet: String
    /// Bullet 2: Aerobic stability and time to cardiac drift.
    public let efficiencyScoreBullet: String
    /// Bullet 3: Cadence and biomechanical form consistency.
    public let formInsightBullet: String

    // Summary strip formatted values (Hollow view renderers)
    public let elapsedFormatted: String
    public let distanceFormatted: String
    public let averagePaceFormatted: String
    public let averageHeartRateFormatted: String
    public let averageCadenceFormatted: String

    public init(
        adaptationsBullet: String,
        efficiencyScoreBullet: String,
        formInsightBullet: String,
        elapsedFormatted: String,
        distanceFormatted: String,
        averagePaceFormatted: String,
        averageHeartRateFormatted: String,
        averageCadenceFormatted: String
    ) {
        self.adaptationsBullet = adaptationsBullet
        self.efficiencyScoreBullet = efficiencyScoreBullet
        self.formInsightBullet = formInsightBullet
        self.elapsedFormatted = elapsedFormatted
        self.distanceFormatted = distanceFormatted
        self.averagePaceFormatted = averagePaceFormatted
        self.averageHeartRateFormatted = averageHeartRateFormatted
        self.averageCadenceFormatted = averageCadenceFormatted
    }
}

// MARK: - AdaptivePacingCore Debrief Builder Extension

extension AdaptivePacingCore {

    /// Builds a deterministic, unit-aware post-run debrief from session accumulators.
    ///
    /// - Parameters:
    ///   - elapsedSeconds: Total workout duration in seconds.
    ///   - totalDistanceMeters: Cumulative distance covered, or `nil` to fall back to the engine's tracked distance.
    ///   - useMetricSystem: Whether to format in metric (km, s/km) or imperial (mi, s/mi) units.
    /// - Returns: A pre-computed, display-ready `WatchRunDebrief`.
    public func buildRunDebrief(
        elapsedSeconds: TimeInterval,
        totalDistanceMeters: Double? = nil,
        useMetricSystem: Bool = true
    ) -> WatchRunDebrief {
        let distance = totalDistanceMeters ?? latestTotalDistanceMeters ?? 0.0

        // Elapsed time formatting
        let totalSecs = max(0, Int(elapsedSeconds.rounded()))
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        let hours = mins / 60
        let elapsedFormatted: String = (hours > 0)
            ? String(format: "%d:%02d:%02d", hours, mins % 60, secs)
            : String(format: "%d:%02d", mins, secs)

        // Distance formatting
        let distanceFormatted: String
        if useMetricSystem {
            let km = distance / 1000.0
            distanceFormatted = String(format: "%.2f km", km)
        } else {
            let miles = distance / 1609.344
            distanceFormatted = String(format: "%.2f mi", miles)
        }

        // Average pace formatting
        let averagePaceFormatted: String
        if distance > 0 && elapsedSeconds > 0 {
            let secPerKm = elapsedSeconds / (distance / 1000.0)
            if useMetricSystem {
                let paceInt = max(0, Int(secPerKm.rounded()))
                averagePaceFormatted = String(format: "%d:%02d /km", paceInt / 60, paceInt % 60)
            } else {
                let paceMile = max(0, Int((secPerKm * 1.609344).rounded()))
                averagePaceFormatted = String(format: "%d:%02d /mi", paceMile / 60, paceMile % 60)
            }
        } else if paceSampleCount > 0 {
            let avgSecsPerKm = totalPaceSumSecondsPerKm / Double(paceSampleCount)
            if useMetricSystem {
                let paceInt = max(0, Int(avgSecsPerKm.rounded()))
                averagePaceFormatted = String(format: "%d:%02d /km", paceInt / 60, paceInt % 60)
            } else {
                let paceMile = max(0, Int((avgSecsPerKm * 1.609344).rounded()))
                averagePaceFormatted = String(format: "%d:%02d /mi", paceMile / 60, paceMile % 60)
            }
        } else {
            averagePaceFormatted = "--:--"
        }

        // Average HR formatting
        let averageHeartRateFormatted: String = (hrSampleCount > 0)
            ? "\(Int((totalHRSum / Double(hrSampleCount)).rounded())) BPM"
            : "--"

        // Average Cadence formatting
        let averageCadenceFormatted: String = (cadenceSampleCount > 0)
            ? "\(Int((totalCadenceSum / Double(cadenceSampleCount)).rounded())) SPM"
            : "--"

        // 1. Adaptations bullet
        let adaptationsBullet: String
        if surgeCount == 0 && recoveryAdjustmentCount == 0 {
            adaptationsBullet = "Held steady baseline pacing throughout."
        } else {
            var parts: [String] = []
            if surgeCount > 0 {
                let surgeNoun = (surgeCount == 1) ? "1 surge" : "\(surgeCount) surges"
                let peakDeltaStr: String
                if useMetricSystem {
                    peakDeltaStr = "+\(peakSurgeDeltaSecondsPerKm)s/km"
                } else {
                    let peakMile = Int((Double(peakSurgeDeltaSecondsPerKm) * 1.609344).rounded())
                    peakDeltaStr = "+\(peakMile)s/mi"
                }
                parts.append("\(surgeNoun) (\(peakDeltaStr) peak)")
            }
            if recoveryAdjustmentCount > 0 {
                let recNoun = (recoveryAdjustmentCount == 1)
                    ? "1 recovery adjustment"
                    : "\(recoveryAdjustmentCount) recovery adjustments"
                parts.append(recNoun)
            }
            adaptationsBullet = parts.joined(separator: ", ") + "."
        }

        // 2. Efficiency score bullet
        let efficiencyScoreBullet: String
        let totalElapsedMinutes = max(1, Int((elapsedSeconds / 60.0).rounded()))
        if let driftSec = firstDriftElapsedSeconds {
            let driftMinutes = max(1, Int((driftSec / 60.0).rounded()))
            efficiencyScoreBullet = "Held baseline efficiency for \(driftMinutes) minutes before cardiac drift."
        } else {
            efficiencyScoreBullet = "Held baseline efficiency for all \(totalElapsedMinutes) minutes."
        }

        // 3. Form insight bullet
        let formInsightBullet: String
        let cadenceValue: Int = cadenceBaselineSPM
            ?? (cadenceSampleCount > 0
                ? Int((totalCadenceSum / Double(cadenceSampleCount)).rounded())
                : (currentTargetCadenceSPM ?? 170))

        if let solidDist = solidCadenceUntilDistanceMeters,
           (useMetricSystem ? solidDist >= 1000.0 : solidDist >= 1609.344) {
            if useMetricSystem {
                let km = max(1, Int((solidDist / 1000.0).rounded()))
                formInsightBullet = "Cadence stayed rock-solid at \(cadenceValue) spm until kilometer \(km)."
            } else {
                let mi = max(1, Int((solidDist / 1609.344).rounded()))
                formInsightBullet = "Cadence stayed rock-solid at \(cadenceValue) spm until mile \(mi)."
            }
        } else {
            formInsightBullet = "Cadence stayed rock-solid at \(cadenceValue) spm across the run."
        }

        return WatchRunDebrief(
            adaptationsBullet: adaptationsBullet,
            efficiencyScoreBullet: efficiencyScoreBullet,
            formInsightBullet: formInsightBullet,
            elapsedFormatted: elapsedFormatted,
            distanceFormatted: distanceFormatted,
            averagePaceFormatted: averagePaceFormatted,
            averageHeartRateFormatted: averageHeartRateFormatted,
            averageCadenceFormatted: averageCadenceFormatted
        )
    }
}
