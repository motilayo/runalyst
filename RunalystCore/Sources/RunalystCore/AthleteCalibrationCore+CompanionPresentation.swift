import Foundation

// MARK: - Watch Companion Pre-Run Presentation

extension WatchResolvedSessionConfig {

    /// Sync status badge summarizing whether today's intent is planned for today, uses a local calibrated profile, or standalone defaults.
    public var companionStatusBadgeText: String {
        if isPhoneSessionSynced {
            return "TODAY'S PLAN"
        }
        if profile.isFallback {
            return "STANDALONE READY"
        }
        return "CALIBRATED PROFILE"
    }

    /// Header pill distinguishing prescribed drills, iPhone-synced daily sessions, and standalone adaptive runs.
    public var sessionHeaderBadgeText: String {
        if hasPrescribedDrill {
            return "PRESCRIBED DRILL"
        }
        if isUserIntentOverride {
            return "CUSTOM INTENT"
        }
        return isPhoneSessionSynced ? "TODAY'S SESSION" : "ADAPTIVE RUN"
    }

    /// Primary human-readable title for the active watch pre-run card.
    public var sessionTitle: String {
        if hasPrescribedDrill {
            return prescribedDrillTitle ?? "Prescribed Drill"
        }
        if isUserIntentOverride {
            return WatchRunIntent.matching(intentKind: intent.intent).title
        }
        switch intent.intent {
        case .recovery:
            return "Easy Recovery"
        case .easyAerobic:
            return "Easy Aerobic Base"
        case .steady:
            return "Aerobic Base"
        case .tempo:
            return "Tempo & Performance"
        case .progression:
            return "Progression Run"
        case .intervals:
            return "Rhythm Intervals"
        }
    }

    /// Concise coaching subtitle explaining the physiological focus of the resolved session.
    public var sessionSubtitle: String {
        if hasPrescribedDrill {
            return "Pre-run neuromuscular primer"
        }
        switch intent.intent {
        case .recovery:
            return "Low-strain cardiac recovery"
        case .easyAerobic:
            return "Conversational aerobic foundation"
        case .steady:
            return "Aerobic rhythm & cadence stability"
        case .tempo:
            return "Controlled threshold effort"
        case .progression:
            return "Steady finish acceleration"
        case .intervals:
            return "High-turnover speed repeats"
        }
    }

    /// Formats the resolved target pace in metric (`/km`) or imperial (`/mi`), returning `"Adaptive"` when absent or non-positive.
    ///
    /// - Parameter useMetric: When `true`, formats seconds per kilometer; when `false`, converts to seconds per mile.
    /// - Returns: A pre-formatted pace string such as `"5:00 /km"`, `"8:03 /mi"`, or `"Adaptive"`.
    public func targetPaceFormatted(useMetric: Bool = true) -> String {
        guard let secondsPerKm = intent.targetPaceSecondsPerKm, secondsPerKm > 0 else {
            return "Adaptive"
        }
        let displaySeconds = useMetric ? secondsPerKm : Int((Double(secondsPerKm) * 1.60934).rounded())
        let unit = useMetric ? "/km" : "/mi"
        return String(format: "%d:%02d %@", displaySeconds / 60, displaySeconds % 60, unit)
    }

    /// Display pill text for target cadence, falling back to `"Adaptive"` when no drill cadence target is active.
    public var targetCadencePillText: String {
        targetCadenceFormatted ?? "Adaptive"
    }

    /// Display pill text for the intent-aware calibrated heart rate ceiling.
    public var aerobicCeilingPillText: String {
        aerobicCeilingPillText(for: intent.intent)
    }

    /// Formats the calibrated heart rate ceiling for a specific pacing intent.
    public func aerobicCeilingPillText(for intentKind: PacingIntentKind) -> String {
        let ceilings = profile.zoneCeilings()
        let ceiling: Int
        if hasPrescribedDrill {
            ceiling = ceilings.zone2BaseBPM
        } else {
            switch intentKind {
            case .recovery:
                ceiling = ceilings.zone1RecoveryBPM
            case .tempo, .progression, .intervals:
                ceiling = ceilings.zone4TempoBPM
            case .easyAerobic, .steady:
                ceiling = ceilings.zone2BaseBPM
            }
        }
        return "<\(ceiling) BPM"
    }

    /// Primary call-to-action button title for launching the resolved workout session.
    public var primaryCtaTitle: String {
        hasPrescribedDrill ? "Start Drill" : "Start Run"
    }
}

// MARK: - Calibrated Zone Ceilings

/// Discrete heart rate zone ceiling boundaries calibrated to an athlete's physiology.
public struct CalibratedZoneCeilings: Sendable, Equatable {
    public let zone1RecoveryBPM: Int
    public let zone2BaseBPM: Int
    public let zone3SteadyBPM: Int
    public let zone4TempoBPM: Int
    public let zone5IntervalBPM: Int

    public init(
        zone1RecoveryBPM: Int,
        zone2BaseBPM: Int,
        zone3SteadyBPM: Int,
        zone4TempoBPM: Int,
        zone5IntervalBPM: Int
    ) {
        self.zone1RecoveryBPM = zone1RecoveryBPM
        self.zone2BaseBPM = zone2BaseBPM
        self.zone3SteadyBPM = zone3SteadyBPM
        self.zone4TempoBPM = zone4TempoBPM
        self.zone5IntervalBPM = zone5IntervalBPM
    }
}

extension AthleteCalibrationProfile {
    /// Computes discrete heart rate zone ceilings using Karvonen HRR (when valid resting HR is available)
    /// or max heart rate percentage fallback.
    public func zoneCeilings() -> CalibratedZoneCeilings {
        if let rhr = restingHR, rhr > 30, maxHR > rhr {
            let hrr = maxHR - rhr
            return CalibratedZoneCeilings(
                zone1RecoveryBPM: Int((rhr + 0.70 * hrr).rounded()),
                zone2BaseBPM: Int((rhr + 0.78 * hrr).rounded()),
                zone3SteadyBPM: Int((rhr + 0.83 * hrr).rounded()),
                zone4TempoBPM: Int((rhr + 0.88 * hrr).rounded()),
                zone5IntervalBPM: Int((rhr + 0.92 * hrr).rounded())
            )
        } else {
            return CalibratedZoneCeilings(
                zone1RecoveryBPM: Int((maxHR * 0.72).rounded()),
                zone2BaseBPM: Int((maxHR * 0.78).rounded()),
                zone3SteadyBPM: Int((maxHR * 0.83).rounded()),
                zone4TempoBPM: Int((maxHR * 0.90).rounded()),
                zone5IntervalBPM: Int((maxHR * 0.93).rounded())
            )
        }
    }
}
