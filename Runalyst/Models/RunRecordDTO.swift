import Foundation

struct RunRecordDTO: Sendable {
    let hkWorkoutID: UUID
    let date: Date
    let totalDistanceMeters: Double
    let duration: TimeInterval
    let rawAvgPace: Double
    let rawAvgHeartRate: Double
    let rawAvgCadence: Double
    let workingAvgPace: Double
    let workingAvgCadence: Double
    let workingAvgHeartRate: Double
    let rawAvgVerticalOscillation: Double?
    let workingAvgVerticalOscillation: Double?
    let rawAvgStrideLength: Double?
    let workingAvgStrideLength: Double?
    let workingDistanceMeters: Double?
    let workingDurationSeconds: Double?
    let isIndoor: Bool?
    let paceCV: Double
    let paceSlope: Double
    let percentZone4: Double
    let detectedTypeRaw: String
    let framboiseTags: [String]
    let dataSourceRaw: String?
    let classificationConfidence: Double?
    let classificationProbabilitiesData: Data?
    let hrCV: Double?
    let cadenceSlope: Double?
    let needsInclineReview: Bool?
    let runSignatureData: Data?
    let ambientTemperatureCelsius: Double?
    let ambientHumidity: Double?

    init(
        hkWorkoutID: UUID,
        date: Date,
        totalDistanceMeters: Double,
        duration: TimeInterval,
        rawAvgPace: Double,
        rawAvgHeartRate: Double,
        rawAvgCadence: Double,
        workingAvgPace: Double,
        workingAvgCadence: Double,
        workingAvgHeartRate: Double,
        rawAvgVerticalOscillation: Double? = nil,
        workingAvgVerticalOscillation: Double? = nil,
        rawAvgStrideLength: Double? = nil,
        workingAvgStrideLength: Double? = nil,
        workingDistanceMeters: Double? = nil,
        workingDurationSeconds: Double? = nil,
        isIndoor: Bool? = nil,
        paceCV: Double,
        paceSlope: Double,
        percentZone4: Double,
        detectedTypeRaw: String,
        framboiseTags: [String] = [],
        dataSourceRaw: String? = nil,
        classificationConfidence: Double? = nil,
        classificationProbabilitiesData: Data? = nil,
        hrCV: Double? = nil,
        cadenceSlope: Double? = nil,
        needsInclineReview: Bool? = nil,
        runSignatureData: Data? = nil,
        ambientTemperatureCelsius: Double? = nil,
        ambientHumidity: Double? = nil
    ) {
        self.hkWorkoutID = hkWorkoutID
        self.date = date
        self.totalDistanceMeters = totalDistanceMeters
        self.duration = duration
        self.rawAvgPace = rawAvgPace
        self.rawAvgHeartRate = rawAvgHeartRate
        self.rawAvgCadence = rawAvgCadence
        self.workingAvgPace = workingAvgPace
        self.workingAvgCadence = workingAvgCadence
        self.workingAvgHeartRate = workingAvgHeartRate
        self.rawAvgVerticalOscillation = rawAvgVerticalOscillation
        self.workingAvgVerticalOscillation = workingAvgVerticalOscillation
        self.rawAvgStrideLength = rawAvgStrideLength
        self.workingAvgStrideLength = workingAvgStrideLength
        self.workingDistanceMeters = workingDistanceMeters
        self.workingDurationSeconds = workingDurationSeconds
        self.isIndoor = isIndoor
        self.paceCV = paceCV
        self.paceSlope = paceSlope
        self.percentZone4 = percentZone4
        self.detectedTypeRaw = detectedTypeRaw
        self.framboiseTags = framboiseTags
        self.dataSourceRaw = dataSourceRaw
        self.classificationConfidence = classificationConfidence
        self.classificationProbabilitiesData = classificationProbabilitiesData
        self.hrCV = hrCV
        self.cadenceSlope = cadenceSlope
        self.needsInclineReview = needsInclineReview
        self.runSignatureData = runSignatureData
        self.ambientTemperatureCelsius = ambientTemperatureCelsius
        self.ambientHumidity = ambientHumidity
    }

    /// Evaluates whether active running heart rate is implausibly low (e.g. < 85 BPM during active running > 5 min and pace < 8:00/km).
    var isHeartRateSensorLowConfidence: Bool {
        guard duration >= 300.0, workingAvgPace > 0, workingAvgPace <= 480.0 else { return false }
        return workingAvgHeartRate > 0 && workingAvgHeartRate < 85.0
    }
}

struct RunBaselineData: Sendable {
    let date: Date
    let pace: Double
    let hr: Double
    let cadence: Double
    var duration: Double = 0.0
    var isPrescribedDrill: Bool = false
}
