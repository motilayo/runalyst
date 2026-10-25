import Foundation
import SwiftUI
import RunalystCore

/// Structured locked training prescription deterministically calculated by Swift.
struct LockedTrainingPrescription: Sendable, Equatable {
    let referencePaceSec: Double?
    let activeGoal: String
    let isSubjectiveOverride: Bool
    let isColdStart: Bool

    // Immediate Next-Session Prescription
    let nextSessionName: String
    let intensityCategory: String
    let prescribedDurationBand: String
    let prescribedPaceBand: String
    let prescribedCadenceBand: String
    let sessionRationale: String

    // Full Training Zone Matrix (Formatted in active unit system)
    let zone1RecoveryPace: String
    let zone2AerobicBasePace: String
    let zone3SteadyPace: String
    let zone4ThresholdPace: String
    let zone5IntervalPace: String

    init(
        referencePaceSec: Double?,
        activeGoal: String,
        isSubjectiveOverride: Bool,
        isColdStart: Bool,
        nextSessionName: String,
        prescribedDurationBand: String,
        prescribedPaceBand: String,
        prescribedCadenceBand: String,
        sessionRationale: String,
        zone1RecoveryPace: String,
        zone2AerobicBasePace: String,
        zone3SteadyPace: String,
        zone4ThresholdPace: String,
        zone5IntervalPace: String,
        intensityCategory: String = "EASY_AEROBIC_ZONE_2"
    ) {
        self.referencePaceSec = referencePaceSec
        self.activeGoal = activeGoal
        self.isSubjectiveOverride = isSubjectiveOverride
        self.isColdStart = isColdStart
        self.nextSessionName = nextSessionName
        self.intensityCategory = intensityCategory
        self.prescribedDurationBand = prescribedDurationBand
        self.prescribedPaceBand = prescribedPaceBand
        self.prescribedCadenceBand = prescribedCadenceBand
        self.sessionRationale = sessionRationale
        self.zone1RecoveryPace = zone1RecoveryPace
        self.zone2AerobicBasePace = zone2AerobicBasePace
        self.zone3SteadyPace = zone3SteadyPace
        self.zone4ThresholdPace = zone4ThresholdPace
        self.zone5IntervalPace = zone5IntervalPace
    }

    /// Compact duration text formatted for target pills and summary badges (e.g. "30–40 Min", "Rest Day").
    var compactDurationBand: String {
        if intensityCategory.contains("REST") || prescribedDurationBand.localizedCaseInsensitiveContains("rest") {
            return "Rest Day"
        }
        return prescribedDurationBand
            .replacingOccurrences(of: " minutes", with: " Min")
            .replacingOccurrences(of: " minute", with: " Min")
    }
}

/// Telemetry and profile input used by TrainingZoneEngine.
struct TrainingZoneInput: Sendable {
    let baselinePaceSec: Double?
    let workoutPaceSec: Double?
    let activeGoal: String
    let experienceLevel: String
    let readyForHard: Bool
    let daysSinceWorkout: Int
    let heightAdjustedCadenceFloor: Int
    let useMetricSystem: Bool
    let userHeightCm: Double
    let isSubjectiveDistress: Bool
    let totalHistoricalRunsCount: Int

    init(
        baselinePaceSec: Double?,
        workoutPaceSec: Double?,
        activeGoal: String,
        experienceLevel: String,
        readyForHard: Bool,
        daysSinceWorkout: Int,
        heightAdjustedCadenceFloor: Int,
        useMetricSystem: Bool,
        userHeightCm: Double = 175.0,
        isSubjectiveDistress: Bool = false,
        totalHistoricalRunsCount: Int = 1
    ) {
        self.baselinePaceSec = baselinePaceSec
        self.workoutPaceSec = workoutPaceSec
        self.activeGoal = activeGoal
        self.experienceLevel = experienceLevel
        self.readyForHard = readyForHard
        self.daysSinceWorkout = daysSinceWorkout
        self.heightAdjustedCadenceFloor = heightAdjustedCadenceFloor
        self.useMetricSystem = useMetricSystem
        self.userHeightCm = userHeightCm
        self.isSubjectiveDistress = isSubjectiveDistress
        self.totalHistoricalRunsCount = totalHistoricalRunsCount
    }
}

/// Swift Training Zone & Prescription Calculator.
enum TrainingZoneEngine {
    private static let assessmentKey = "hasCompletedOnboardingAssessment"

    /// Checks whether the runner has completed their onboarding assessment run.
    static var hasCompletedAssessment: Bool {
        get { UserDefaults.standard.bool(forKey: assessmentKey) }
        set { UserDefaults.standard.set(newValue, forKey: assessmentKey) }
    }

    /// Calculates locked zones and session prescription with cold-start fallbacks and subjective override.
    @MainActor
    static func computePrescription(_ input: TrainingZoneInput, runs: [RunRecord] = []) -> LockedTrainingPrescription {
        // 1. Subjective Override Interception
        if input.isSubjectiveDistress {
            return LockedTrainingPrescription(
                referencePaceSec: input.baselinePaceSec ?? input.workoutPaceSec,
                activeGoal: input.activeGoal,
                isSubjectiveOverride: true,
                isColdStart: false,
                nextSessionName: "Full Rest & Recovery (Health Override)",
                prescribedDurationBand: "0 minutes (Full Rest Day)",
                prescribedPaceBand: "N/A",
                prescribedCadenceBand: "N/A",
                sessionRationale: "Subjective physical illness, fever, or acute strain reported. Immune recovery and physical safety supersede all training prescriptions.",
                zone1RecoveryPace: "N/A",
                zone2AerobicBasePace: "N/A",
                zone3SteadyPace: "N/A",
                zone4ThresholdPace: "N/A",
                zone5IntervalPace: "N/A",
                intensityCategory: "FULL_REST_OVERRIDE"
            )
        }

        // 2. Cold Start Fallback Hierarchy
        let hasRuns = !runs.isEmpty || input.totalHistoricalRunsCount > 0
        let hasGraduated = hasCompletedAssessment || hasRuns

        // Determine reference anchor pace
        let anchorPace: Double
        let isColdStart: Bool

        if let base = input.baselinePaceSec, base > 0 {
            anchorPace = base
            isColdStart = false
        } else if let current = input.workoutPaceSec, current > 0 {
            anchorPace = current
            isColdStart = false
            // Record completion of first run to graduate from assessment
            if !hasCompletedAssessment {
                hasCompletedAssessment = true
            }
        } else if hasGraduated {
            // Graduated from assessment but no pace available yet (e.g. manual transition)
            anchorPace = defaultPaceForExperience(input.experienceLevel)
            isColdStart = false
        } else {
            // Tier 3: Zero-day cold start novice assessment
            anchorPace = defaultPaceForExperience(input.experienceLevel)
            isColdStart = true
        }

        // Cold Start Tier 3 Novice Assessment
        if isColdStart && input.experienceLevel.contains("Novice") {
            return LockedTrainingPrescription(
                referencePaceSec: nil,
                activeGoal: input.activeGoal,
                isSubjectiveOverride: false,
                isColdStart: true,
                nextSessionName: "20-Minute Baseline Assessment (Run/Walk)",
                prescribedDurationBand: "20–25 minutes",
                prescribedPaceBand: "Conversational Effort (Alternate 2 min easy jog / 1 min walk)",
                prescribedCadenceBand: "\(input.heightAdjustedCadenceFloor)–\(input.heightAdjustedCadenceFloor + 6) SPM",
                sessionRationale: "Welcome to Runalyst! We need one baseline session to establish your aerobic profile before setting specific pacing zones.",
                zone1RecoveryPace: "Conversational Walk/Jog",
                zone2AerobicBasePace: "Easy Conversational (can talk in full sentences)",
                zone3SteadyPace: "Moderate Effort",
                zone4ThresholdPace: "Comfortably Hard",
                zone5IntervalPace: "Brisk Strides",
                intensityCategory: "EASY_AEROBIC_ASSESSMENT"
            )
        }

        // 3. Mathematical Zone Calculation (Tier 1 & Tier 2) via RunalystCore
        let matrix = TrainingZoneCore.calculateZones(anchorPaceSecPerKm: anchorPace, activeGoal: input.activeGoal)
        let z1Str = matrix.zone1Recovery.formatted(useMetric: input.useMetricSystem)
        let z2Str = matrix.zone2AerobicBase.formatted(useMetric: input.useMetricSystem)
        let z3Str = matrix.zone3Steady.formatted(useMetric: input.useMetricSystem)
        let z4Str = matrix.zone4Threshold.formatted(useMetric: input.useMetricSystem)
        let z5Str = matrix.zone5Interval.formatted(useMetric: input.useMetricSystem)

        // 4. Delegate Next-Session Prescription to SessionSynthesisEngine (Single Source of Truth)
        let effectiveRuns: [RunRecord]
        if !runs.isEmpty {
            effectiveRuns = runs
        } else {
            let runDate = Calendar.current.date(byAdding: .day, value: -max(1, input.daysSinceWorkout), to: Date()) ?? Date().addingTimeInterval(-86400)
            let repRun = RunRecord(
                hkWorkoutID: UUID(),
                date: runDate,
                totalDistanceMeters: 5000.0,
                duration: anchorPace * 5.0,
                rawAvgPace: anchorPace,
                rawAvgHeartRate: input.readyForHard ? 142.0 : 168.0,
                rawAvgCadence: Double(input.heightAdjustedCadenceFloor),
                workingAvgPace: anchorPace,
                workingAvgCadence: Double(input.heightAdjustedCadenceFloor),
                workingAvgHeartRate: input.readyForHard ? 142.0 : 168.0,
                paceCV: 0.05,
                paceSlope: 0.0,
                percentZone4: 0.1,
                detectedTypeRaw: input.readyForHard ? "Steady Effort" : "Recovery Jog"
            )
            if !input.readyForHard {
                repRun.framboiseTags = [FramboiseReadinessTag.cardiacDrift]
            }
            effectiveRuns = [repRun]
        }

        let dailyState = DailyTrainingStateStore.shared.resolveState(
            runRecords: effectiveRuns,
            activeGoal: input.activeGoal,
            experienceLevel: input.experienceLevel,
            useMetric: input.useMetricSystem,
            userHeightCm: input.userHeightCm,
            now: Date()
        )

        let session: PrescribedDailySession = {
            switch dailyState {
            case .preRun(let s): return s
            case .completedToday(_, let tomorrow): return tomorrow
            }
        }()

        let nextName = session.sessionTitle
        let nextDur = session.durationBand
        let nextPace = session.paceBand
        let nextCad = session.primerTargetCadence.isEmpty ? "\(input.heightAdjustedCadenceFloor)–\(input.heightAdjustedCadenceFloor + 6) SPM" : session.primerTargetCadence
        let rationale = session.groundedRationale
        let category: String = {
            if session.isRestDay || session.mainSessionTemplateId == .aerobicFlush || session.mainSessionTemplateId == .recoveryJog {
                return "RECOVERY_FLUSH_ZONE_1"
            } else if session.mainSessionTemplateId == .tempoSurges {
                return "THRESHOLD_ZONE_4"
            } else if session.mainSessionTemplateId == .rhythmIntervals {
                return "INTERVAL_ZONE_5"
            } else {
                return "EASY_AEROBIC_ZONE_2"
            }
        }()

        return LockedTrainingPrescription(
            referencePaceSec: anchorPace,
            activeGoal: input.activeGoal,
            isSubjectiveOverride: false,
            isColdStart: isColdStart,
            nextSessionName: nextName,
            prescribedDurationBand: nextDur,
            prescribedPaceBand: nextPace,
            prescribedCadenceBand: nextCad,
            sessionRationale: rationale,
            zone1RecoveryPace: z1Str,
            zone2AerobicBasePace: z2Str,
            zone3SteadyPace: z3Str,
            zone4ThresholdPace: z4Str,
            zone5IntervalPace: z5Str,
            intensityCategory: category
        )
    }

    /// Delegates directly to SessionSynthesisEngine while supplying the athlete's actual RunRecord history.
    @MainActor
    static func computePrescription(
        runs: [RunRecord],
        profile: RunnerProfile? = nil,
        activeGoal: String = "Base Building",
        experienceLevel: String = "Intermediate",
        useMetricSystem: Bool = true,
        userHeightCm: Double = 175.0,
        isSubjectiveDistress: Bool = false,
        now: Date = Date()
    ) -> LockedTrainingPrescription {
        let latestRun = runs.first(where: { !$0.isDeleted })
        let baselinePace = latestRun?.workingAvgPace
        let actualHeight = profile?.userHeightCm ?? userHeightCm
        let cadenceFloor = profile?.heightAdjustedCadenceFloor ?? Int((150.0 / (max(130.0, min(220.0, actualHeight)) / 175.0)).rounded())
        let daysSince = latestRun.map { Calendar.current.dateComponents([.day], from: $0.date, to: now).day ?? 0 } ?? 0

        let input = TrainingZoneInput(
            baselinePaceSec: baselinePace,
            workoutPaceSec: latestRun?.workingAvgPace,
            activeGoal: activeGoal,
            experienceLevel: experienceLevel,
            readyForHard: true,
            daysSinceWorkout: daysSince,
            heightAdjustedCadenceFloor: cadenceFloor,
            useMetricSystem: useMetricSystem,
            userHeightCm: actualHeight,
            isSubjectiveDistress: isSubjectiveDistress,
            totalHistoricalRunsCount: runs.count
        )
        return computePrescription(input, runs: runs)
    }

    private static func defaultPaceForExperience(_ level: String) -> Double {
        if level.contains("Elite") {
            return 255.0 // ~4:15/km
        } else if level.contains("Advanced") || level.contains("Veteran") {
            return 290.0 // ~4:50/km
        } else if level.contains("Intermediate") || level.contains("Enthusiast") {
            return 340.0 // ~5:40/km
        } else {
            return 400.0 // ~6:40/km (Novice)
        }
    }

    private static func formatRange(lowSec: Double, highSec: Double, useMetric: Bool) -> String {
        let low = Int(lowSec.rounded())
        let high = Int(highSec.rounded())
        let p1M = low / 60
        let p1S = low % 60
        let p2M = high / 60
        let p2S = high % 60
        if useMetric {
            return String(format: "%d:%02d–%d:%02d/km", p1M, p1S, p2M, p2S)
        } else {
            let lowMi = Int((lowSec * 1.609344).rounded())
            let highMi = Int((highSec * 1.609344).rounded())
            let mi1M = lowMi / 60
            let mi1S = lowMi % 60
            let mi2M = highMi / 60
            let mi2S = highMi % 60
            return String(format: "%d:%02d–%d:%02d/mi", mi1M, mi1S, mi2M, mi2S)
        }
    }
}
