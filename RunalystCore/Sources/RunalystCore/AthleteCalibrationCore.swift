import Foundation

// MARK: - Calibration Profile & Session Intent

/// Athlete cardiovascular calibration profile derived on iPhone and published to Apple Watch.
public struct AthleteCalibrationProfile: Sendable, Codable, Equatable {
    /// Sustained observed maximum heart rate (or Tanaka / default fallback).
    public let maxHR: Double
    /// Median 30-day resting heart rate, if available.
    public let restingHR: Double?
    /// 75th percentile of historical power-to-HR ratio during steady runs.
    public let powerToHRTopQuartile: Double?
    /// Whether this profile was generated from fallbacks rather than direct telemetry.
    public let isFallback: Bool

    public init(
        maxHR: Double,
        restingHR: Double? = nil,
        powerToHRTopQuartile: Double? = nil,
        isFallback: Bool = false
    ) {
        self.maxHR = maxHR
        self.restingHR = restingHR
        self.powerToHRTopQuartile = powerToHRTopQuartile
        self.isFallback = isFallback
    }
}

/// Category of workout pacing intent governing state machine trigger permissions.
public enum PacingIntentKind: String, Sendable, Codable {
    case recovery
    case easyAerobic
    case steady
    case tempo
    case progression
    case intervals
}

/// The runner's training intent and target pace for a specific calendar day.
public struct PacingSessionIntent: Sendable, Codable, Equatable {
    /// Prescribed target pace in seconds per kilometer (e.g. 300 for 5:00 /km), or `nil` for "Just Run".
    public let targetPaceSecondsPerKm: Int?
    /// Physiological category of the session.
    public let intent: PacingIntentKind
    /// Whether subjective distress was reported, triggering safety overrides.
    public let subjectiveDistress: Bool
    /// ISO-8601 day identifier ("yyyy-MM-dd", en_US_POSIX) for which this intent is valid.
    public let validForDay: String

    public init(
        targetPaceSecondsPerKm: Int? = nil,
        intent: PacingIntentKind = .steady,
        subjectiveDistress: Bool = false,
        validForDay: String
    ) {
        self.targetPaceSecondsPerKm = targetPaceSecondsPerKm
        self.intent = intent
        self.subjectiveDistress = subjectiveDistress
        self.validForDay = validForDay
    }
}

/// Versioned payload transferred from iPhone to Apple Watch via `WCSession.updateApplicationContext`.
public struct WatchPacingContext: Sendable, Codable, Equatable {
    public static let currentSchemaVersion: Int = 1

    /// Schema version for forward-compatibility validation.
    public let schemaVersion: Int
    /// Athlete physiological calibration profile.
    public let profile: AthleteCalibrationProfile
    /// Today's synthesized training intent.
    public let intent: PacingSessionIntent

    public init(
        schemaVersion: Int = WatchPacingContext.currentSchemaVersion,
        profile: AthleteCalibrationProfile,
        intent: PacingSessionIntent
    ) {
        self.schemaVersion = schemaVersion
        self.profile = profile
        self.intent = intent
    }

    /// Whether the watch app's compiled runtime supports this schema version.
    public var isSupportedSchema: Bool {
        schemaVersion <= WatchPacingContext.currentSchemaVersion
    }
}

/// Discrete target pace selection option presented on Apple Watch.
public struct WatchTargetPaceOption: Identifiable, Sendable, Codable, Equatable, Hashable {
    public let id: String
    public let paceSecondsPerKm: Int?
    public let label: String

    public init(id: String, paceSecondsPerKm: Int?, label: String) {
        self.id = id
        self.paceSecondsPerKm = paceSecondsPerKm
        self.label = label
    }

    /// Default option where no explicit pace is targeted, adapting around the athlete's natural baseline.
    public static let justRun = WatchTargetPaceOption(
        id: "just-run",
        paceSecondsPerKm: nil,
        label: "Just Run"
    )

    /// Standard presets ranging from 4:00 /km (240 s) to 8:00 /km (480 s) in 15-second steps.
    public static let allOptions: [WatchTargetPaceOption] = {
        var options: [WatchTargetPaceOption] = [.justRun]
        for pace in stride(from: 240, through: 480, by: 15) {
            let minutes = pace / 60
            let seconds = pace % 60
            let label = String(format: "%d:%02d /km", minutes, seconds)
            options.append(WatchTargetPaceOption(id: "\(pace)", paceSecondsPerKm: pace, label: label))
        }
        return options
    }()
}

/// Resolved runtime configuration for an Apple Watch workout session.
public struct WatchResolvedSessionConfig: Sendable, Equatable {
    public let profile: AthleteCalibrationProfile
    public let intent: PacingSessionIntent
    public let requiresTargetPacePicker: Bool

    public init(
        profile: AthleteCalibrationProfile,
        intent: PacingSessionIntent,
        requiresTargetPacePicker: Bool
    ) {
        self.profile = profile
        self.intent = intent
        self.requiresTargetPacePicker = requiresTargetPacePicker
    }
}

// MARK: - Athlete Calibration Core Engine

/// Pure mathematical engine for deriving athlete calibration and mapping training prescriptions.
public enum AthleteCalibrationCore {

    /// Derives an athlete's calibration profile from historical buckets and resting heart rate samples.
    ///
    /// - Parameters:
    ///   - buckets: Historical telemetry buckets across prior running sessions.
    ///   - restingHRSamples: Resting heart rate samples recorded within the trailing 30 days.
    ///   - age: Chronological age for Tanaka fallback derivation if history lacks a 60 s peak.
    ///   - windowEnd: Anchor date for temporal scoping without dynamic wall-clock dependencies.
    public static func makeProfile(
        buckets: [TelemetryBucket],
        restingHRSamples: [Double] = [],
        age: Int? = nil,
        windowEnd: Date
    ) -> AthleteCalibrationProfile {
        let window180Days: TimeInterval = 180.0 * 86400.0
        let windowStart180 = windowEnd.addingTimeInterval(-window180Days)

        // 1. Derive maxHR: sustained 60 s peak over [windowEnd - 180d, windowEnd]
        let recentBuckets = buckets.filter { $0.timestamp >= windowStart180 && $0.timestamp <= windowEnd }
        var observedPeakHR: Double?

        // Check buckets with duration >= 60s
        for bucket in recentBuckets where bucket.durationSeconds >= 60.0 && bucket.heartRateBPM > 0 {
            if let current = observedPeakHR {
                observedPeakHR = max(current, bucket.heartRateBPM)
            } else {
                observedPeakHR = bucket.heartRateBPM
            }
        }

        // Check adjacent buckets for shorter slices (e.g. 30s slices)
        let sorted = recentBuckets.sorted { $0.timestamp < $1.timestamp }
        if (observedPeakHR ?? 0) < 100.0, sorted.count >= 2 {
            for i in 0..<(sorted.count - 1) {
                let b1 = sorted[i]
                let b2 = sorted[i + 1]
                let timeGap = b2.timestamp.timeIntervalSince(b1.timestamp)
                if timeGap <= (b1.durationSeconds + 5.0) && (b1.durationSeconds + b2.durationSeconds) >= 55.0 {
                    let sustained = min(b1.heartRateBPM, b2.heartRateBPM)
                    if sustained > 0 {
                        if let current = observedPeakHR {
                            observedPeakHR = max(current, sustained)
                        } else {
                            observedPeakHR = sustained
                        }
                    }
                }
            }
        }

        let maxHR: Double
        let isFallback: Bool

        if let peak = observedPeakHR, peak >= 100.0 {
            maxHR = peak
            isFallback = false
        } else if let runnerAge = age, runnerAge > 0 {
            // Tanaka formula: 208 - 0.7 * age
            maxHR = 208.0 - 0.7 * Double(runnerAge)
            isFallback = true
        } else {
            maxHR = 190.0
            isFallback = true
        }

        // 2. Derive restingHR: median of resting HR samples
        let restingHR: Double? = {
            guard !restingHRSamples.isEmpty else { return nil }
            let sorted = restingHRSamples.filter { $0 > 0 }.sorted()
            guard !sorted.isEmpty else { return nil }
            let mid = sorted.count / 2
            if sorted.count % 2 == 1 {
                return sorted[mid]
            } else {
                return (sorted[mid - 1] + sorted[mid]) / 2.0
            }
        }()

        // 3. Derive powerToHRTopQuartile: 75th percentile of bucket power/HR
        let powerToHRTopQuartile: Double? = {
            let validRatios = recentBuckets.compactMap { bucket -> Double? in
                guard let power = bucket.powerWatts, power > 0, bucket.heartRateBPM > 0 else {
                    return nil
                }
                return power / bucket.heartRateBPM
            }.sorted()

            guard !validRatios.isEmpty else { return nil }
            let index = Int((Double(validRatios.count - 1) * 0.75).rounded())
            return validRatios[index]
        }()

        return AthleteCalibrationProfile(
            maxHR: maxHR,
            restingHR: restingHR,
            powerToHRTopQuartile: powerToHRTopQuartile,
            isFallback: isFallback
        )
    }

    /// Generates a safe fallback profile when no historical telemetry is available on-device.
    public static func fallbackProfile(age: Int? = nil) -> AthleteCalibrationProfile {
        let maxHR: Double = {
            if let runnerAge = age, runnerAge > 0 {
                return 208.0 - 0.7 * Double(runnerAge)
            }
            return 190.0
        }()

        return AthleteCalibrationProfile(
            maxHR: maxHR,
            restingHR: nil,
            powerToHRTopQuartile: nil,
            isFallback: true
        )
    }

    // MARK: - Prescription Mapping

    /// Maps a `SessionSynthesisCore` planned session specification to a watchOS `PacingSessionIntent`.
    public static func makeIntent(
        spec: PlannedSessionSpec?,
        subjectiveDistress: Bool = false,
        day: String,
        targetPaceSecondsPerKm: Int? = nil
    ) -> PacingSessionIntent {
        // Protection Mandate: Subjective distress forces recovery intent and overrides race goals
        if subjectiveDistress {
            return PacingSessionIntent(
                targetPaceSecondsPerKm: targetPaceSecondsPerKm ?? parseTargetPace(from: spec?.paceBand),
                intent: .recovery,
                subjectiveDistress: true,
                validForDay: day
            )
        }

        guard let spec else {
            return PacingSessionIntent(
                targetPaceSecondsPerKm: targetPaceSecondsPerKm,
                intent: .steady,
                subjectiveDistress: false,
                validForDay: day
            )
        }

        let resolvedIntent: PacingIntentKind = {
            if spec.intent == .fullRest || spec.intent == .recoveryFlush {
                return .recovery
            }
            let title = spec.title.lowercased()
            if title.contains("recovery") {
                return .recovery
            }
            if title.contains("interval") || title.contains("stride") || title.contains("hill repeat") {
                return .intervals
            }
            if title.contains("tempo") || title.contains("threshold") {
                return .tempo
            }
            if title.contains("progression") {
                return .progression
            }
            if title.contains("steady") {
                return .steady
            }
            if title.contains("easy") || title.contains("base") || title.contains("zone 2") {
                return .easyAerobic
            }
            return .steady
        }()

        let resolvedPace = targetPaceSecondsPerKm ?? parseTargetPace(from: spec.paceBand)

        return PacingSessionIntent(
            targetPaceSecondsPerKm: resolvedPace,
            intent: resolvedIntent,
            subjectiveDistress: false,
            validForDay: day
        )
    }

    /// Convenience alias for `makeIntent`.
    public static func intent(
        for spec: PlannedSessionSpec?,
        subjectiveDistress: Bool = false,
        day: String,
        targetPaceSecondsPerKm: Int? = nil
    ) -> PacingSessionIntent {
        makeIntent(
            spec: spec,
            subjectiveDistress: subjectiveDistress,
            day: day,
            targetPaceSecondsPerKm: targetPaceSecondsPerKm
        )
    }

    // MARK: - Pure Date String Helpers

    /// Formats a pure date into an ISO-8601 calendar day string ("yyyy-MM-dd") using explicit calendar.
    public static func formatDayString(date: Date, calendar: Calendar) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Validates whether a context's declared day matches the specified current day string.
    public static func isContextValidForDay(_ context: WatchPacingContext, currentDayString: String) -> Bool {
        context.intent.validForDay == currentDayString
    }

    /// Validates whether a session intent's declared day matches the specified current day string.
    public static func isContextValidForDay(_ intent: PacingSessionIntent, currentDayString: String) -> Bool {
        intent.validForDay == currentDayString
    }

    /// Resolves the watch session's calibration profile and pacing intent from local cache and current day.
    ///
    /// - Parameters:
    ///   - cachedContext: The most recently cached `WatchPacingContext` received from iPhone, if any.
    ///   - currentDayString: Today's calendar date string ("yyyy-MM-dd", en_US_POSIX) provided by the caller.
    ///   - selectedTargetPaceSecondsPerKm: Runner-selected pace option on watch (defaults to `nil` for "Just Run").
    ///   - fallbackAge: Chronological age for Tanaka derivation if no profile exists.
    /// - Returns: A resolved session configuration indicating whether a pace picker is required.
    public static func resolveWatchSession(
        cachedContext: WatchPacingContext?,
        currentDayString: String,
        selectedTargetPaceSecondsPerKm: Int? = nil,
        fallbackAge: Int? = nil
    ) -> WatchResolvedSessionConfig {
        guard let cachedContext, cachedContext.isSupportedSchema else {
            // Case 1: No cached context or unsupported schema -> Fallback profile + picker required
            let maxHR: Double = {
                if let age = fallbackAge, age > 0 {
                    return 208.0 - (0.7 * Double(age))
                }
                return 190.0
            }()
            let fallbackProfile = AthleteCalibrationProfile(
                maxHR: maxHR,
                restingHR: nil,
                powerToHRTopQuartile: nil,
                isFallback: true
            )
            let intent = PacingSessionIntent(
                targetPaceSecondsPerKm: selectedTargetPaceSecondsPerKm,
                intent: .steady,
                subjectiveDistress: false,
                validForDay: currentDayString
            )
            return WatchResolvedSessionConfig(
                profile: fallbackProfile,
                intent: intent,
                requiresTargetPacePicker: true
            )
        }

        if cachedContext.intent.validForDay == currentDayString {
            // Case 2: Fresh context for today -> Use profile & intent directly, no picker required
            let finalTarget = selectedTargetPaceSecondsPerKm ?? cachedContext.intent.targetPaceSecondsPerKm
            let resolvedIntent = PacingSessionIntent(
                targetPaceSecondsPerKm: finalTarget,
                intent: cachedContext.intent.intent,
                subjectiveDistress: cachedContext.intent.subjectiveDistress,
                validForDay: cachedContext.intent.validForDay
            )
            return WatchResolvedSessionConfig(
                profile: cachedContext.profile,
                intent: resolvedIntent,
                requiresTargetPacePicker: false
            )
        } else {
            // Case 3: Stale intent from prior day -> Reuse profile, reset to steady intent + require picker
            let intent = PacingSessionIntent(
                targetPaceSecondsPerKm: selectedTargetPaceSecondsPerKm,
                intent: .steady,
                subjectiveDistress: false,
                validForDay: currentDayString
            )
            return WatchResolvedSessionConfig(
                profile: cachedContext.profile,
                intent: intent,
                requiresTargetPacePicker: true
            )
        }
    }

    // MARK: - Private Helpers


    private static func parseTargetPace(from paceBand: String?) -> Int? {
        guard let paceBand else { return nil }

        // If band contains a range like "5:15 - 5:35 /km", take the midpoint
        if paceBand.contains("-") {
            let components = paceBand.split(separator: "-")
            if components.count == 2,
               let p1 = WorkoutMathCalculatorCore.parsePaceSeconds(from: String(components[0])),
               let p2 = WorkoutMathCalculatorCore.parsePaceSeconds(from: String(components[1])) {
                return Int(((p1 + p2) / 2.0).rounded())
            }
        }

        if let seconds = WorkoutMathCalculatorCore.parsePaceSeconds(from: paceBand) {
            return Int(seconds.rounded())
        }

        return nil
    }
}
