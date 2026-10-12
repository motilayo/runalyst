import Foundation

/// Represents a segmented time window in a run (work interval, recovery interval, steady cruising, or walking break).
struct PhaseSegment: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(startSeconds)-\(endSeconds)-\(kind)" }
    let startSeconds: Double
    let endSeconds: Double
    let kind: String // "work", "recovery", "steady", "walking"
    let avgPace: Double
    let avgCadence: Double
    let avgHR: Double

    var durationSeconds: Double {
        max(0, endSeconds - startSeconds)
    }
}

/// Represents a continuous 1-kilometer (or mile) distance split.
struct RunSplit: Codable, Sendable, Equatable, Identifiable {
    var id: Int { index }
    let index: Int                  // 1, 2, 3... (km 1, km 2...)
    let distanceMeters: Double      // Distance covered in this split (e.g. 1000m)
    let durationSeconds: Double     // Duration in seconds
    let paceSecondsPerKm: Double    // Pace in seconds per kilometer
    let avgHeartRate: Double        // Average heart rate during this split
    let avgCadence: Double          // Average cadence during this split
    let elevationGainMeters: Double // Net elevation gain
}

/// Represents the persisted mathematical signature and structural classification of a run.
/// Computed strictly once at ingestion to power the interactive RAG Analyst chat and Variance Map without battery drain.
struct RunSignature: Codable, Sendable, Equatable {
    let classification: String
    let confidence: Double
    let probabilities: [String: Double]
    let anomalies: [String]
    let cadenceFloor: Double
    let phaseSegments: [PhaseSegment]
    let dataSource: String // "wrist", "gymkit", "footpod"
    let isIndoor: Bool
    let needsInclineReview: Bool
    let splits: [RunSplit]

    enum CodingKeys: String, CodingKey {
        case classification, confidence, probabilities, anomalies, cadenceFloor
        case phaseSegments, dataSource, isIndoor, needsInclineReview, splits
    }

    init(
        classification: String,
        confidence: Double,
        probabilities: [String: Double],
        anomalies: [String],
        cadenceFloor: Double,
        phaseSegments: [PhaseSegment],
        dataSource: String,
        isIndoor: Bool,
        needsInclineReview: Bool,
        splits: [RunSplit] = []
    ) {
        self.classification = classification
        self.confidence = confidence
        self.probabilities = probabilities
        self.anomalies = anomalies
        self.cadenceFloor = cadenceFloor
        self.phaseSegments = phaseSegments
        self.dataSource = dataSource
        self.isIndoor = isIndoor
        self.needsInclineReview = needsInclineReview
        self.splits = splits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        classification = try container.decode(String.self, forKey: .classification)
        confidence = try container.decode(Double.self, forKey: .confidence)
        probabilities = try container.decode([String: Double].self, forKey: .probabilities)
        anomalies = try container.decode([String].self, forKey: .anomalies)
        cadenceFloor = try container.decode(Double.self, forKey: .cadenceFloor)
        phaseSegments = try container.decode([PhaseSegment].self, forKey: .phaseSegments)
        dataSource = try container.decode(String.self, forKey: .dataSource)
        isIndoor = try container.decode(Bool.self, forKey: .isIndoor)
        needsInclineReview = try container.decode(Bool.self, forKey: .needsInclineReview)
        splits = (try? container.decode([RunSplit].self, forKey: .splits)) ?? []
    }

    /// Formats this signature into a token-efficient compact key-value block for FoundationModels prompts.
    var compactRAGSummary: String {
        var lines: [String] = []
        lines.append("Workout Type: \(classification)")
        lines.append("Classification Confidence: \(Int(confidence * 100))%")
        lines.append("Sensor Source: \(dataSource.capitalized)")
        lines.append("Environment: \(isIndoor ? "Indoor Treadmill" : "Outdoor Road/Trail")")
        lines.append("Cadence Floor: \(Int(cadenceFloor)) SPM")
        if !anomalies.isEmpty {
            lines.append("Telemetry Highlights: \(anomalies.joined(separator: ", "))")
        }
        if needsInclineReview {
            lines.append("Incline Note: Potential Incline Intervals Detected")
        }
        let workSegments = phaseSegments.filter { $0.kind == "work" }
        let recoverySegments = phaseSegments.filter { $0.kind == "recovery" }
        if !workSegments.isEmpty {
            lines.append("Interval Structure: \(workSegments.count) work reps, \(recoverySegments.count) recovery reps")
        }
        if !splits.isEmpty {
            lines.append("Splits: \(splits.count) kilometer splits recorded")
        }
        return lines.joined(separator: "\n")
    }
}
