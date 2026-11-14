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

    /// Display pill text for the Karvonen (or max-HR percentage fallback) 78% aerobic heart rate ceiling.
    public var aerobicCeilingPillText: String {
        let cap: Int
        if let resting = profile.restingHR, resting > 0, profile.maxHR > resting {
            cap = Int((resting + 0.78 * (profile.maxHR - resting)).rounded())
        } else {
            cap = Int((profile.maxHR * 0.78).rounded())
        }
        return "<\(cap) BPM"
    }

    /// Primary call-to-action button title for launching the resolved workout session.
    public var primaryCtaTitle: String {
        hasPrescribedDrill ? "Start Drill" : "Start Run"
    }
}
