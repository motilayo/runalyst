import SwiftUI

/// Context-driven hero card that dynamically renders either Heart Rate Trajectory or Cadence Rhythm
/// based on workout classification, while allowing the runner to toggle between modalities.
struct AdaptiveWorkoutTelemetryCard: View {
    let runRecord: RunRecord
    let phaseSegments: [PhaseSegment]
    let cadenceFloor: Double
    let averageCadence: Double
    var workoutDuration: Double?
    var isIntervalOrDrill: Bool = true
    var workoutType: String?

    @State private var selectedModality: WorkoutTelemetryModality

    init(
        runRecord: RunRecord,
        phaseSegments: [PhaseSegment],
        cadenceFloor: Double,
        averageCadence: Double,
        workoutDuration: Double? = nil,
        isIntervalOrDrill: Bool = true,
        workoutType: String? = nil
    ) {
        self.runRecord = runRecord
        self.phaseSegments = phaseSegments
        self.cadenceFloor = cadenceFloor
        self.averageCadence = averageCadence
        self.workoutDuration = workoutDuration
        self.isIntervalOrDrill = isIntervalOrDrill
        self.workoutType = workoutType
        _selectedModality = State(initialValue: WorkoutTelemetryModalityResolver.defaultModality(for: runRecord))
    }

    private var canToggle: Bool {
        runRecord.workingAvgHeartRate > 0 && !runRecord.isHeartRateSensorLowConfidence
    }

    var body: some View {
        let ceilings = SessionSynthesisEngine.calibratedCeilings(for: runRecord)
        let z1 = ceilings.map { Double($0.zone1RecoveryBPM) } ?? 135.0
        let z2 = ceilings.map { Double($0.zone2BaseBPM) } ?? 144.0

        Group {
            if selectedModality == .heartRate && canToggle {
                HeartRateTrajectoryMapView(
                    phaseSegments: phaseSegments,
                    workingAvgHeartRate: runRecord.workingAvgHeartRate,
                    workoutDuration: workoutDuration ?? runRecord.duration,
                    workoutType: workoutType ?? runRecord.detectedTypeRaw,
                    zone1Ceiling: z1,
                    zone2Ceiling: z2,
                    percentZone4: runRecord.percentZone4,
                    hrCV: runRecord.hrCV,
                    splits: runRecord.signature?.splits ?? [],
                    rawAvgHeartRate: runRecord.rawAvgHeartRate,
                    selectedModality: canToggle ? $selectedModality : nil
                )
            } else {
                RunVarianceMapView(
                    phaseSegments: phaseSegments,
                    cadenceFloor: cadenceFloor,
                    averageCadence: averageCadence,
                    workoutDuration: workoutDuration ?? runRecord.duration,
                    isIntervalOrDrill: isIntervalOrDrill,
                    workoutType: workoutType ?? runRecord.detectedTypeRaw,
                    selectedModality: canToggle ? $selectedModality : nil
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedModality)
    }
}
