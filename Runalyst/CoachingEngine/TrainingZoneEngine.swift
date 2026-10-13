import Foundation
import SwiftUI

/// Structured locked training prescription deterministically calculated by Swift.
struct LockedTrainingPrescription: Sendable, Equatable {
    let referencePaceSec: Double?
    let activeGoal: String
    let isSubjectiveOverride: Bool
    let isColdStart: Bool

    // Immediate Next-Session Prescription
    let nextSessionName: String
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

    var promptDescription: String {
        var lines: [String] = []
        lines.append("LOCKED TRAINING ZONES & SESSION PRESCRIPTION:")
        if isSubjectiveOverride {
            lines.append("- OVERRIDE ACTIVE: Subjective illness or acute distress reported.")
            lines.append("- Recommended Action: \(nextSessionName)")
            lines.append("- Prescribed Duration: \(prescribedDurationBand)")
            lines.append("- Prescribed Pacing: \(prescribedPaceBand)")
            lines.append("- Rationale: \(sessionRationale)")
            lines.append("RULE: Safety and recovery override all race goals. Direct the runner to rest and sleep.")
            return lines.joined(separator: "\n")
        }

        lines.append("- Next Recommended Session: \(nextSessionName)")
        lines.append("- Prescribed Duration: \(prescribedDurationBand)")
        lines.append("- Prescribed Target Pace: \(prescribedPaceBand)")
        lines.append("- Prescribed Target Cadence: \(prescribedCadenceBand)")
        lines.append("- Prescription Rationale: \(sessionRationale)")
        lines.append("- Zone 1 (Recovery Flush): \(zone1RecoveryPace)")
        lines.append("- Zone 2 (Easy Aerobic Base): \(zone2AerobicBasePace)")
        lines.append("- Zone 3 (Steady Aerobic): \(zone3SteadyPace)")
        lines.append("- Zone 4 (Lactate Threshold): \(zone4ThresholdPace)")
        lines.append("- Zone 5 (Goal Interval Reps): \(zone5IntervalPace)")
        lines.append("RULE: You must quote paces and durations exclusively from this pre-calculated table. You have zero authority to invent or guess custom target numbers.")
        return lines.joined(separator: "\n")
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
    static func computePrescription(_ input: TrainingZoneInput) -> LockedTrainingPrescription {
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
                zone5IntervalPace: "N/A"
            )
        }

        // 2. Cold Start Fallback Hierarchy
        let hasRuns = input.totalHistoricalRunsCount > 0
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
                zone5IntervalPace: "Brisk Strides"
            )
        }

        // 3. Mathematical Zone Calculation (Tier 1 & Tier 2)
        let z1PaceLow = anchorPace + 60.0
        let z1PaceHigh = anchorPace + 90.0

        let z2PaceLow = anchorPace + 30.0
        let z2PaceHigh = anchorPace + 50.0

        let z3PaceLow = anchorPace + 10.0
        let z3PaceHigh = anchorPace + 25.0

        let z4PaceLow = anchorPace - 10.0
        let z4PaceHigh = anchorPace + 5.0

        // Zone 5 Goal Calibration
        let z5PaceLow: Double
        let z5PaceHigh: Double
        if input.activeGoal.contains("5K") {
            z5PaceLow = anchorPace - 30.0
            z5PaceHigh = anchorPace - 20.0
        } else if input.activeGoal.contains("10K") {
            z5PaceLow = anchorPace - 20.0
            z5PaceHigh = anchorPace - 10.0
        } else if input.activeGoal.contains("Half") {
            z5PaceLow = anchorPace - 10.0
            z5PaceHigh = anchorPace
        } else {
            z5PaceLow = anchorPace - 5.0
            z5PaceHigh = anchorPace + 10.0
        }

        let z1Str = formatRange(lowSec: z1PaceLow, highSec: z1PaceHigh, useMetric: input.useMetricSystem)
        let z2Str = formatRange(lowSec: z2PaceLow, highSec: z2PaceHigh, useMetric: input.useMetricSystem)
        let z3Str = formatRange(lowSec: z3PaceLow, highSec: z3PaceHigh, useMetric: input.useMetricSystem)
        let z4Str = formatRange(lowSec: z4PaceLow, highSec: z4PaceHigh, useMetric: input.useMetricSystem)
        let z5Str = formatRange(lowSec: z5PaceLow, highSec: z5PaceHigh, useMetric: input.useMetricSystem)

        // 4. Next Session Prescription
        let nextName: String
        let nextDur: String
        let nextPace: String
        let nextCad: String
        let rationale: String

        if !input.readyForHard {
            nextName = "Zone 1 Active Recovery Flush"
            nextDur = "25–35 minutes"
            nextPace = z1Str
            nextCad = "\(input.heightAdjustedCadenceFloor - 2)–\(input.heightAdjustedCadenceFloor + 4) SPM"
            rationale = "You are currently in an active recovery window. Keep effort gentle to flush metabolic waste without muscular breakdown."
        } else if input.daysSinceWorkout >= 2 {
            nextName = "Zone 2 Easy Aerobic Base"
            nextDur = "35–45 minutes"
            nextPace = z2Str
            nextCad = "\(input.heightAdjustedCadenceFloor)–\(input.heightAdjustedCadenceFloor + 6) SPM"
            rationale = "You have had full rest days and are completely recovered. Ready to build aerobic capillary density at conversational pace."
        } else {
            nextName = "Zone 2 Easy Aerobic Maintenance"
            nextDur = "30–40 minutes"
            nextPace = z2Str
            nextCad = "\(input.heightAdjustedCadenceFloor)–\(input.heightAdjustedCadenceFloor + 6) SPM"
            rationale = "Cleared for training. Build continuous aerobic base toward your goal of \(input.activeGoal)."
        }

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
            zone5IntervalPace: z5Str
        )
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
            return String(format: "%d:%02d–%d:%02d/km (%d:%02d–%d:%02d/mi)", p1M, p1S, p2M, p2S, mi1M, mi1S, mi2M, mi2S)
        }
    }
}
