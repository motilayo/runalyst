import Foundation
import CoreML

/// Structured classification result including confidence, full probability distribution, and incline inference.
struct ClassificationResult: Sendable, Equatable {
    let targetClass: String
    let confidence: Double
    let probabilities: [String: Double]
    let isReviewRequired: Bool
    let needsInclineReview: Bool
}

/// A manager for interfacing with the CoreML RunalystClassifier.
actor ModelManager {

    // CoreML integration
    private var runClassifier: RunalystClassifier?

    init() {
        do {
            let config = MLModelConfiguration()
            self.runClassifier = try RunalystClassifier(configuration: config)
        } catch {
            print("Failed to load RunalystClassifier: \(error)")
        }
    }

    /// Predicts the run type using the CoreML model and returns a rich ClassificationResult.
    func predictRunTypeResult(
        buckets: [BucketData],
        paceDelta: Double,
        hrDelta: Double,
        percentZone4: Double,
        cadenceDelta: Double,
        verticalOscillation: Double = 9.5,
        runnerStage: Int = 1,
        cv: Double = 0.05,
        slope: Double = 0.0,
        durationMinutes: Double = 30.0,
        cadenceCV: Double = 0.0,
        hrCV: Double = 0.035,
        cadenceSlope: Double = 0.0,
        isIndoor: Bool = false,
        isGymKit: Bool = false,
        rawAverageHR: Double? = nil
    ) async -> ClassificationResult {
        let framboise = FramboiseEngine()
        let effectiveBuckets = isIndoor ? await framboise.filterRunningSamples(buckets: buckets) : buckets
        let activeBuckets = effectiveBuckets.isEmpty ? buckets : effectiveBuckets
        let cycles = await framboise.extractOscillationCycles(buckets: activeBuckets)
        let weightedClass = await framboise.classifyRun(
            buckets: activeBuckets,
            cv: cv,
            slope: slope,
            zone4: percentZone4,
            durationMinutes: durationMinutes,
            cadenceCV: cadenceCV,
            averageHR: rawAverageHR,
            paceDelta: paceDelta,
            hrDelta: hrDelta,
            cycles: cycles,
            isIndoor: isIndoor
        )

        // Incline Inference: Apple Watch barometric altimeter cannot detect treadmill inclines.
        let needsInclineReview = Self.shouldFlagForInclineReview(
            isIndoor: isIndoor,
            isGymKit: isGymKit,
            hrCV: hrCV,
            cv: cv,
            cadenceSlope: cadenceSlope,
            cadenceDelta: cadenceDelta
        )

        // Indoor Treadmill: belt artificially locks pace and wrist accelerometer is erratic.
        // If not connected to GymKit ground-truth, deprioritize pace_cv and pace_slope.
        let effectiveCV = (isIndoor && !isGymKit) ? 0.035 : cv
        let effectiveSlope = (isIndoor && !isGymKit) ? 0.0 : slope

        if let classifier = self.runClassifier {
            do {
                let input = RunalystClassifierInput(
                    paceDelta: paceDelta,
                    hrDelta: hrDelta,
                    percentZone4: percentZone4,
                    cadenceDelta: cadenceDelta,
                    verticalOscillation: verticalOscillation,
                    cv: effectiveCV,
                    paceSlope: effectiveSlope,
                    runnerStage: Double(runnerStage),
                    durationMinutes: durationMinutes,
                    cadenceCV: cadenceCV,
                    hrCV: hrCV
                )
                let prediction = try await classifier.prediction(input: input)
                var targetClass = prediction.targetClass
                let rawProbabilities = prediction.classProbability

                // Normalize probabilities:
                // RunalystClassifier (RandomForestClassifier with 150 trees) outputs tree vote sums (sum ~ 150.0).
                let totalVotes = rawProbabilities.values.reduce(0.0, +)
                let probabilities: [String: Double]
                if totalVotes > 1.01 {
                    probabilities = rawProbabilities.mapValues { $0 / totalVotes }
                } else {
                    probabilities = rawProbabilities
                }
                let maxProb = probabilities.values.max() ?? 0.0

                // Human-in-the-Loop Confidence Threshold (ADR-0005):
                // If the classifier outputs normalized probability < 75%, refuse to guess and flag for user review.
                var isLowConfidence = maxProb < 0.75
                if isLowConfidence {
                    targetClass = "Mixed Effort (Review)"
                }

                // Topological Structural Guardrails (exempt from low confidence flag as they are deterministic truth):
                // 1. Continuous Run Gate:
                if (prediction.targetClass == "Fartlek" || prediction.targetClass == "Intervals" || prediction.targetClass == "Pyramids") && cycles.count < 3 {
                    targetClass = weightedClass
                    isLowConfidence = false
                }

                // 2. Intermittent Gate:
                if cycles.count >= 3 && targetClass != "Intervals" && targetClass != "Fartlek" && targetClass != "Pyramids" {
                    targetClass = weightedClass
                    isLowConfidence = false
                }

                // 3. Environmental & Topographic Override (Bidirectional & Indoor aware):
                // Urban Traffic and Hill Repeats can NEVER occur indoors on a treadmill.
                // Furthermore, Urban Traffic / Hill Repeats require deterministic topological corroboration from FramboiseEngine.
                if (prediction.targetClass == "Urban Traffic" || prediction.targetClass == "Hill Repeats") && isIndoor {
                    targetClass = weightedClass
                    isLowConfidence = false
                } else if (targetClass == "Urban Traffic" || targetClass == "Hill Repeats") && weightedClass != targetClass {
                    targetClass = weightedClass
                    isLowConfidence = false
                } else if (weightedClass == "Urban Traffic" || weightedClass == "Hill Repeats") && !isIndoor {
                    targetClass = weightedClass
                    isLowConfidence = false
                }

                return ClassificationResult(
                    targetClass: targetClass,
                    confidence: maxProb,
                    probabilities: probabilities,
                    isReviewRequired: isLowConfidence || targetClass == "Mixed Effort (Review)",
                    needsInclineReview: needsInclineReview
                )
            } catch {
                print("CoreML prediction failed: \(error). Falling back to FramboiseEngine.")
            }
        }

        return ClassificationResult(
            targetClass: weightedClass,
            confidence: 0.85,
            probabilities: [weightedClass: 0.85],
            isReviewRequired: false,
            needsInclineReview: needsInclineReview
        )
    }

    /// Backward-compatible string prediction convenience.
    func predictRunType(
        buckets: [BucketData],
        paceDelta: Double,
        hrDelta: Double,
        percentZone4: Double,
        cadenceDelta: Double,
        verticalOscillation: Double = 9.5,
        runnerStage: Int = 1,
        cv: Double = 0.05,
        slope: Double = 0.0,
        durationMinutes: Double = 30.0,
        cadenceCV: Double = 0.0,
        hrCV: Double = 0.035,
        cadenceSlope: Double = 0.0,
        isIndoor: Bool = false,
        isGymKit: Bool = false,
        rawAverageHR: Double? = nil
    ) async -> String {
        let result = await predictRunTypeResult(
            buckets: buckets,
            paceDelta: paceDelta,
            hrDelta: hrDelta,
            percentZone4: percentZone4,
            cadenceDelta: cadenceDelta,
            verticalOscillation: verticalOscillation,
            runnerStage: runnerStage,
            cv: cv,
            slope: slope,
            durationMinutes: durationMinutes,
            cadenceCV: cadenceCV,
            hrCV: hrCV,
            cadenceSlope: cadenceSlope,
            isIndoor: isIndoor,
            isGymKit: isGymKit,
            rawAverageHR: rawAverageHR
        )
        return result.targetClass
    }

    /// Pure deterministic incline inference rule.
    static func shouldFlagForInclineReview(
        isIndoor: Bool,
        isGymKit: Bool,
        hrCV: Double,
        cv: Double,
        cadenceSlope: Double,
        cadenceDelta: Double = 0.0
    ) -> Bool {
        guard isIndoor && !isGymKit else { return false }
        return hrCV > 0.075 && cv < 0.045 && (cadenceSlope < -0.005 || cadenceDelta < -2.0)
    }
}

extension RunalystClassifier: @unchecked Sendable {}
extension RunalystClassifierOutput: @unchecked Sendable {}
