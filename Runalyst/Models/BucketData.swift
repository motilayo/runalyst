import Foundation

/// Represents a single slice of a run for analysis (nominally 60s, but can be 30s or variable).
struct BucketData: Sendable {
    let startTime: Date
    let distanceMeters: Double
    let durationSeconds: Double
    let meanPaceSecPerKm: Double
    let meanCadence: Double
    let meanHR: Double
    let meanVerticalOscillation: Double
    let meanStrideLength: Double
    let elevationGainMeters: Double

    init(
        startTime: Date,
        distanceMeters: Double,
        durationSeconds: Double = 60.0,
        meanPaceSecPerKm: Double,
        meanCadence: Double,
        meanHR: Double,
        meanVerticalOscillation: Double = 0.0,
        meanStrideLength: Double = 0.0,
        elevationGainMeters: Double = 0.0
    ) {
        self.startTime = startTime
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.meanPaceSecPerKm = meanPaceSecPerKm
        self.meanCadence = meanCadence
        self.meanHR = meanHR
        self.meanVerticalOscillation = meanVerticalOscillation
        self.meanStrideLength = meanStrideLength
        self.elevationGainMeters = elevationGainMeters
    }
}

/// Represents a detected work (surge) and recovery oscillation pair.
struct SurgeRecoveryCycle: Sendable {
    let workDuration: Double
    let recoveryDuration: Double
    let workCadence: Double
    let recoveryCadence: Double
    let workPace: Double
    let recoveryPace: Double
    let workHR: Double
    let recoveryHR: Double
    let isCorroborated: Bool
}

/// Structural topological analysis result for run classification.
struct TopologicalSignature: Sendable {
    let validCycles: [SurgeRecoveryCycle]
    let regularityScore: Double
    var validCycleCount: Int { validCycles.count }
    var isIntermittent: Bool { validCycleCount >= 3 }
}
