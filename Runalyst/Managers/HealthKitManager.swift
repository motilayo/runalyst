import Foundation
import HealthKit
import SwiftData
#if canImport(WorkoutKit)
@preconcurrency import WorkoutKit
#endif

protocol HKHealthStoreProtocol: AnyObject, Sendable {
    func requestAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
    func statusForAuthorizationRequest(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws -> HKAuthorizationRequestStatus
    func enableBackgroundDelivery(for type: HKObjectType, frequency: HKUpdateFrequency) async throws
    nonisolated func execute(_ query: HKQuery)
}

extension HKHealthStore: HKHealthStoreProtocol {}

enum DateFilter {
    case sevenDays
    case thirtyDays
    case allTime
}

@MainActor
class HealthKitManager: ObservableObject {
    typealias RunBaselineData = Runalyst.RunBaselineData
    static let shared = HealthKitManager()
    var healthStore: HKHealthStoreProtocol?
    var isHealthDataAvailable: () -> Bool

    @Published var isAuthorized: Bool = false
    var onWorkoutsUpdated: (@Sendable () async -> Void)?
    var workoutFetcher: ((UUID) async throws -> HKWorkout?)?
    var runRecordExtractor: ((HKWorkout, FramboiseEngine, [RunBaselineData]) async throws -> RunRecordDTO)?
    private var observerQuery: HKObserverQuery?

    init(
        healthStore: HKHealthStoreProtocol? = nil,
        isHealthDataAvailable: @escaping () -> Bool = { HKHealthStore.isHealthDataAvailable() }
    ) {
        self.isHealthDataAvailable = isHealthDataAvailable
        if let healthStore = healthStore {
            self.healthStore = healthStore
        } else if isHealthDataAvailable() {
            self.healthStore = HKHealthStore()
        }
    }

    var allTypesToRead: Set<HKObjectType> {
        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .runningSpeed,
            .stepCount,
            .distanceWalkingRunning,
            .runningVerticalOscillation,
            .vo2Max,
            .runningGroundContactTime,
            .runningStrideLength,
            .runningPower,
            .height
        ]
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        for identifier in quantityIdentifiers {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        return types
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable() else {
            throw HKError(.errorHealthDataUnavailable)
        }

        try await healthStore?.requestAuthorization(toShare: [], read: allTypesToRead)

        let workoutStatus = healthStore?.authorizationStatus(for: HKObjectType.workoutType())
        self.isAuthorized = (workoutStatus == .sharingAuthorized) || (workoutStatus == .notDetermined)
        self.isAuthorized = true

        try await enableBackgroundDelivery()
    }

    func enableBackgroundDelivery() async throws {
        try await healthStore?.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate)
    }

    func getRequestStatusForAuthorization() async throws -> HKAuthorizationRequestStatus {
        guard isHealthDataAvailable(), let store = healthStore else {
            return .unknown
        }
        return try await store.statusForAuthorizationRequest(toShare: [], read: allTypesToRead)
    }

    func startObservingWorkouts() {
        guard observerQuery == nil else { return }
        let query = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }
            nonisolated(unsafe) let handler = completionHandler
            Task { @MainActor in
                await self?.onWorkoutsUpdated?()
                handler()
            }
        }
        observerQuery = query
        healthStore?.execute(query)
    }

    func fetchRunningWorkouts(filter: DateFilter = .allTime) async throws -> [HKWorkout] {
        var subpredicates = [HKQuery.predicateForWorkouts(with: .running)]

        switch filter {
        case .sevenDays:
            if let date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) {
                subpredicates.append(HKQuery.predicateForSamples(withStart: date, end: nil, options: .strictStartDate))
            }
        case .thirtyDays:
            if let date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) {
                subpredicates.append(HKQuery.predicateForSamples(withStart: date, end: nil, options: .strictStartDate))
            }
        case .allTime:
            break
        }

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }

                // If not explicitly set, UserDefaults bool defaults to false, but we want our default to be metric if locale is metric
                let hasMetricKey = UserDefaults.standard.object(forKey: "useMetricSystem") != nil
                let useMetricSystem = hasMetricKey ? UserDefaults.standard.bool(forKey: "useMetricSystem") : (Locale.current.measurementSystem == .metric)

                let hasMinDistKey = UserDefaults.standard.object(forKey: "minimumRunDistance") != nil
                let minimumRunDistance = hasMinDistKey ? UserDefaults.standard.double(forKey: "minimumRunDistance") : 1.0

                let minDistanceInMeters = useMetricSystem ? (minimumRunDistance * 1000.0) : (minimumRunDistance * 1609.344)

                let filteredWorkouts = workouts.filter { workout in
                    let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0.0
                    return distance >= minDistanceInMeters
                }

                continuation.resume(returning: filteredWorkouts)
            }
            healthStore?.execute(query)
        }
    }

    func fetchWorkout(with uuid: UUID) async throws -> HKWorkout? {
        if let workoutFetcher = workoutFetcher {
            return try await workoutFetcher(uuid)
        }
        let predicate = HKQuery.predicateForObject(with: uuid)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples?.first as? HKWorkout)
            }
            healthStore?.execute(query)
        }
    }

    func fetchRecentGlobalVO2Maxes(limit: Int = 2) async throws -> [Double] {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: .vo2Max) else {
            return []
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }
                let vo2s = samples.map { $0.quantity.doubleValue(for: HKUnit(from: "ml/kg*min")) }
                continuation.resume(returning: vo2s)
            }
            healthStore?.execute(query)
        }
    }

    func fetchUserHeight() async throws -> Double? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: .height) else {
            return nil
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let samples = samples as? [HKQuantitySample], let latest = samples.first else {
                    continuation.resume(returning: nil)
                    return
                }
                let heightCm = latest.quantity.doubleValue(for: HKUnit.meterUnit(with: .centi))
                continuation.resume(returning: heightCm)
            }
            healthStore?.execute(query)
        }
    }

    func fetchVO2MaxClosestTo(date: Date) async throws -> Double? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: .vo2Max) else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: date, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let samples = samples as? [HKQuantitySample], let first = samples.first else {
                    continuation.resume(returning: nil)
                    return
                }
                let vo2 = first.quantity.doubleValue(for: HKUnit(from: "ml/kg*min"))
                continuation.resume(returning: vo2)
            }
            healthStore?.execute(query)
        }
    }

    // MARK: - Bucketing & Extraction

    func fetchBucketedSamples(for workout: HKWorkout) async throws -> [BucketData] {
        guard let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
              let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
              let oscType = HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation) else {
            return []
        }
        let strideType = HKObjectType.quantityType(forIdentifier: .runningStrideLength)

        async let distanceStats = fetchCollection(for: workout, type: distanceType, options: .cumulativeSum)
        async let stepStats = fetchCollection(for: workout, type: stepType, options: .cumulativeSum)
        async let hrStats = fetchCollection(for: workout, type: hrType, options: .discreteAverage)
        async let oscStats = fetchCollection(for: workout, type: oscType, options: .discreteAverage)
        async let strideStats: [Date: HKStatistics] = {
            guard let strideType = strideType else { return [:] }
            return (try? await fetchCollection(for: workout, type: strideType, options: .discreteAverage)) ?? [:]
        }()

        let (distances, steps, hrs, oscs, strides) = try await (distanceStats, stepStats, hrStats, oscStats, strideStats)

        var buckets: [BucketData] = []
        var currentDate = workout.startDate

        while currentDate < workout.endDate {
            let nextDate = currentDate.addingTimeInterval(15)
            let actualEndDate = min(nextDate, workout.endDate)
            let durationSeconds = actualEndDate.timeIntervalSince(currentDate)
            guard durationSeconds > 0 else { break }

            let distance = distances[currentDate]?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
            let stepCount = steps[currentDate]?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            let hr = hrs[currentDate]?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0
            let osc = oscs[currentDate]?.averageQuantity()?.doubleValue(for: HKUnit.meterUnit(with: .centi)) ?? 0
            let stride = strides[currentDate]?.averageQuantity()?.doubleValue(for: .meter()) ?? 0

            let cadence = durationSeconds > 0 ? (stepCount / (durationSeconds / 60.0)) : 0
            let pace = distance > 0 ? (durationSeconds / (distance / 1000.0)) : 0

            buckets.append(BucketData(
                startTime: currentDate,
                distanceMeters: distance,
                durationSeconds: durationSeconds,
                meanPaceSecPerKm: pace,
                meanCadence: cadence,
                meanHR: hr,
                meanVerticalOscillation: osc,
                meanStrideLength: stride
            ))

            currentDate = nextDate
        }

        return buckets
    }

    func generateOverlappingWindows(from chunks: [BucketData]) -> [BucketData] {
        var windows: [BucketData] = []
        guard !chunks.isEmpty else { return windows }

        let chunksPerWindow = 2 // 2 * 15s = 30s window

        for i in 0..<chunks.count {
            let windowChunks = Array(chunks[i..<min(i + chunksPerWindow, chunks.count)])
            let totalDuration = windowChunks.reduce(0.0) { $0 + $1.durationSeconds }
            let totalDistance = windowChunks.reduce(0.0) { $0 + $1.distanceMeters }
            let totalSteps = windowChunks.reduce(0.0) { $0 + ($1.meanCadence * ($1.durationSeconds / 60.0)) }

            var totalHR = 0.0
            var hrCount = 0.0
            var totalOsc = 0.0
            var oscCount = 0.0

            for chunk in windowChunks {
                if chunk.meanHR > 0 {
                    totalHR += chunk.meanHR * chunk.durationSeconds
                    hrCount += chunk.durationSeconds
                }
                if chunk.meanVerticalOscillation > 0 {
                    totalOsc += chunk.meanVerticalOscillation * chunk.durationSeconds
                    oscCount += chunk.durationSeconds
                }
            }

            let pace = totalDistance > 0 ? (totalDuration / (totalDistance / 1000.0)) : 0.0
            let cadence = totalDuration > 0 ? (totalSteps / (totalDuration / 60.0)) : 0.0
            let hr = hrCount > 0 ? (totalHR / hrCount) : 0.0
            let osc = oscCount > 0 ? (totalOsc / oscCount) : 0.0

            windows.append(BucketData(
                startTime: windowChunks[0].startTime,
                distanceMeters: totalDistance,
                durationSeconds: totalDuration,
                meanPaceSecPerKm: pace,
                meanCadence: cadence,
                meanHR: hr,
                meanVerticalOscillation: osc
            ))
        }
        return windows
    }

    private func fetchCollection(for workout: HKWorkout, type: HKQuantityType, options: HKStatisticsOptions) async throws -> [Date: HKStatistics] {
        return try await withCheckedThrowingContinuation { continuation in
            let workoutPredicate = HKQuery.predicateForObjects(from: workout)
            let datePredicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [])
            let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [workoutPredicate, datePredicate])
            var interval = DateComponents()
            interval.second = 15

            // Align to workout start
            let anchor = workout.startDate

            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchor,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                var statsDict: [Date: HKStatistics] = [:]
                results?.enumerateStatistics(from: workout.startDate, to: workout.endDate) { stats, _ in
                    statsDict[stats.startDate] = stats
                }

                continuation.resume(returning: statsDict)
            }

            healthStore?.execute(query)
        }
    }

    func extractRunRecord(from workout: HKWorkout, engine: FramboiseEngine, priorRuns: [RunBaselineData] = []) async throws -> RunRecordDTO {
        let duration = workout.duration
        let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0.0

        let rawAvgPace = distance > 0 ? (duration / (distance / 1000.0)) : 0.0

        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
              let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let oscType = HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation) else {
            throw NSError(domain: "HealthKitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Required HealthKit quantity types unavailable"])
        }

        let rawAvgHeartRate = try await fetchAverage(for: workout, type: hrType, unit: HKUnit.count().unitDivided(by: .minute()))
        let totalSteps = try await fetchSum(for: workout, type: stepType, unit: HKUnit.count())

        let rawAvgOscillation = try? await fetchAverage(for: workout, type: oscType, unit: HKUnit.meterUnit(with: .centi))
        let strideType = HKObjectType.quantityType(forIdentifier: .runningStrideLength)
        let rawAvgStride: Double?
        if let strideType = strideType {
            rawAvgStride = try? await fetchAverage(for: workout, type: strideType, unit: .meter())
        } else {
            rawAvgStride = nil
        }
        let isIndoorMetadata: Bool? = {
            if let num = workout.metadata?[HKMetadataKeyIndoorWorkout] as? NSNumber {
                return num.boolValue
            }
            if let b = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool {
                return b
            }
            if let num = workout.metadata?["HKIndoorWorkout"] as? NSNumber {
                return num.boolValue
            }
            if let b = workout.metadata?["HKIndoorWorkout"] as? Bool {
                return b
            }
            return nil
        }()
        let isGymKitMachine = (workout.metadata?[HKMetadataKeyFitnessMachineDuration] != nil) ||
            (workout.device?.manufacturer?.localizedCaseInsensitiveContains("GymKit") == true)
        let isIndoor = isIndoorMetadata ?? (isGymKitMachine ? true : false)
        let hasFootpod = isIndoor && ((rawAvgStride ?? 0) > 0 || (rawAvgOscillation ?? 0) > 0)
        let dataSource: String
        if isGymKitMachine {
            dataSource = "gymkit"
        } else if hasFootpod {
            dataSource = "footpod"
        } else if isIndoor {
            dataSource = "wrist"
        } else {
            dataSource = "wrist"
        }

        let rawBuckets = try await fetchBucketedSamples(for: workout)
        // If indoor and uncalibrated wrist accelerometer, apply defensive pace smoothing
        let buckets = (isIndoor && !isGymKitMachine)
            ? await engine.applyIndoorWristPaceSmoothing(buckets: rawBuckets)
            : rawBuckets

        let trimmed = await engine.trimDeadStops(buckets: buckets)
        let (workingPace, workingCadence, workingHR, workingOscillation, workingDistance, workingDuration, workingStride) = await engine.calculateWorkingAverages(
            trimmed: trimmed,
            rawWorkoutDuration: duration,
            rawWorkoutDistance: distance,
            originalBucketCount: buckets.count,
            rawAvgStrideLength: rawAvgStride
        )

        // Raw cadence is total moving steps over the entire elapsed time (including pauses)
        let rawAvgCadence: Double = duration > 0 ? (totalSteps / (duration / 60.0)) : 0.0

        let overlappingWindows = generateOverlappingWindows(from: trimmed)

        let paces = overlappingWindows.map { $0.meanPaceSecPerKm }
        let hrs = overlappingWindows.map { $0.meanHR }
        let cadences = overlappingWindows.map { $0.meanCadence }

        let cv = await engine.calculatePaceCV(bucketPaces: paces)
        let slope = await engine.calculatePaceSlope(bucketPaces: paces)
        let cadenceCV = await engine.calculateCadenceCV(bucketCadences: cadences)
        let hrCV = await engine.calculateHRCV(bucketHRs: hrs)
        let cadenceSlope = await engine.calculateCadenceSlope(bucketCadences: cadences)

        var dynamicZone4Threshold: Double = 161.5
        var dynamicZone2Threshold: Double = 142.0
        var dynamicZone1Threshold: Double = 125.0

        if #available(iOS 27.0, *),
           let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           let actualStore = healthStore as? NSObject {
            let sel = NSSelectorFromString("preferredWorkoutZoneConfigurationForQuantityType:completion:")
            if actualStore.responds(to: sel) {
                struct DynamicZoneThresholds: Sendable {
                    let zone1Max: Double?
                    let zone2Max: Double?
                    let zone4Min: Double?
                }
                let thresholds: DynamicZoneThresholds? = await withCheckedContinuation { continuation in
                    typealias CompletionHandler = @convention(block) (AnyObject?, NSError?) -> Void
                    let handler: CompletionHandler = { config, _ in
                        if let config = config {
                            let extracted = DrillPatternRecognizer.extractZoneThresholds(from: config)
                            continuation.resume(returning: DynamicZoneThresholds(
                                zone1Max: extracted.zone1Max,
                                zone2Max: extracted.zone2Max,
                                zone4Min: extracted.zone4Min
                            ))
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }
                    _ = actualStore.perform(sel, with: hrType, with: handler)
                }
                if let thresholds = thresholds {
                    if let z4 = thresholds.zone4Min {
                        dynamicZone4Threshold = z4
                    }
                    if let z2 = thresholds.zone2Max {
                        dynamicZone2Threshold = z2
                    }
                    if let z1 = thresholds.zone1Max {
                        dynamicZone1Threshold = z1
                    }
                }
            }
        }
        let engineMaxHR = dynamicZone4Threshold / 0.85
        let zone4 = await engine.calculatePercentZone4(bucketHRs: hrs, maxHR: engineMaxHR)

        let validRawOsc = (rawAvgOscillation ?? 0) > 0 ? rawAvgOscillation : nil
        let validWorkingOsc = workingOscillation > 0 ? workingOscillation : validRawOsc
        let finalRawOsc = validRawOsc ?? validWorkingOsc

        let validRawStride = (rawAvgStride ?? 0) > 0 ? rawAvgStride : nil
        let validWorkingStride = (workingStride ?? 0) > 0 ? workingStride : validRawStride
        let finalRawStride = validRawStride ?? validWorkingStride

        let currentPace = workingPace > 0 ? workingPace : rawAvgPace
        let currentHR = workingHR > 0 ? workingHR : rawAvgHeartRate
        let currentCadence = workingCadence > 0 ? workingCadence : rawAvgCadence

        let targetDate = workout.startDate
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: targetDate) ?? Date()

        // Filter prior runs to rolling 30-day window (every run counts)
        let validPriorRuns = priorRuns.filter {
            $0.date >= thirtyDaysAgo &&
            $0.date < targetDate
        }

        let computedBaselineCadence: Double? = {
            guard !validPriorRuns.isEmpty else { return nil }
            let totalCadenceDuration = validPriorRuns.map(\.duration).reduce(0, +)
            if totalCadenceDuration > 0 {
                return validPriorRuns.map { $0.cadence * $0.duration }.reduce(0, +) / totalCadenceDuration
            } else {
                return validPriorRuns.map(\.cadence).reduce(0, +) / Double(validPriorRuns.count)
            }
        }()

        var customWorkoutPlan: CustomWorkout?
        #if canImport(WorkoutKit)
        if #available(iOS 17.0, *) {
            if let plan = try? await workout.workoutPlan {
                if case .custom(let custom) = plan.workout {
                    customWorkoutPlan = custom
                }
            }
        }
        #endif

        // Multi-tiered drill recognition (WorkoutKit metadata, structural activities/laps, intent heuristic, autonomous pattern recognition)
        let matchedDrillIntent = WorkoutBridge.matchDrill(
            workout: workout,
            durationSeconds: duration,
            buckets: buckets,
            baselineCadence: computedBaselineCadence.map(Int.init),
            zone4Threshold: dynamicZone4Threshold,
            zone2Threshold: dynamicZone2Threshold,
            zone1Threshold: dynamicZone1Threshold,
            customWorkout: customWorkoutPlan
        )

        let classification: String
        var classificationResult: ClassificationResult?
        let modelManager = ModelManager()

        // Check for scheduled continuous aerobic sessions from WorkoutKit / CustomWorkout
        let explicitContinuousAerobic: PreRunDrillId? = {
            #if canImport(WorkoutKit)
            if let custom = customWorkoutPlan, let name = custom.displayName, let resolved = PreRunDrillId.resolve(from: name), resolved.isAerobicContinuous {
                return resolved
            }
            #endif
            if let meta = workout.metadata {
                for str in WorkoutBridge.extractAllStrings(from: meta) {
                    if let resolved = PreRunDrillId.resolve(from: str), resolved.isAerobicContinuous {
                        return resolved
                    }
                }
            }
            return nil
        }()

        if let matchedDrill = matchedDrillIntent {
            let matchedClass = PreRunDrillId.correspondingClassification(for: matchedDrill.drillTitle)
                ?? PreRunDrillId.correspondingClassification(for: matchedDrill.preRunDrillId ?? "")
                ?? "Intervals"
            classification = matchedClass
            classificationResult = ClassificationResult(
                targetClass: matchedClass,
                confidence: 1.0,
                probabilities: [matchedClass: 1.0],
                isReviewRequired: false,
                needsInclineReview: false
            )
        } else if let continuousWorkout = explicitContinuousAerobic, zone4 <= 0.20 && cv < 0.10 && duration < 4080 {
            let matchedClass = continuousWorkout.correspondingClassification
            classification = matchedClass
            classificationResult = ClassificationResult(
                targetClass: matchedClass,
                confidence: 1.0,
                probabilities: [matchedClass: 1.0],
                isReviewRequired: false,
                needsInclineReview: false
            )
        } else if !validPriorRuns.isEmpty {
            let aerobicPriorRuns = validPriorRuns.filter { !($0.duration < 1200 && $0.isPrescribedDrill) }

            let totalAerobicDuration = aerobicPriorRuns.map(\.duration).reduce(0, +)
            let totalCadenceDuration = validPriorRuns.map(\.duration).reduce(0, +)

            let baselinePace: Double
            let baselineHR: Double
            let baselineCadence: Double

            if totalAerobicDuration > 0 {
                baselinePace = aerobicPriorRuns.map { $0.pace * $0.duration }.reduce(0, +) / totalAerobicDuration
                baselineHR = aerobicPriorRuns.map { $0.hr * $0.duration }.reduce(0, +) / totalAerobicDuration
            } else {
                baselinePace = aerobicPriorRuns.isEmpty ? (validPriorRuns.map(\.pace).reduce(0, +) / Double(validPriorRuns.count)) : (aerobicPriorRuns.map(\.pace).reduce(0, +) / Double(aerobicPriorRuns.count))
                baselineHR = aerobicPriorRuns.isEmpty ? (validPriorRuns.map(\.hr).reduce(0, +) / Double(validPriorRuns.count)) : (aerobicPriorRuns.map(\.hr).reduce(0, +) / Double(aerobicPriorRuns.count))
            }

            if totalCadenceDuration > 0 {
                baselineCadence = validPriorRuns.map { $0.cadence * $0.duration }.reduce(0, +) / totalCadenceDuration
            } else {
                baselineCadence = validPriorRuns.map(\.cadence).reduce(0, +) / Double(validPriorRuns.count)
            }
            let calculatedStage: Int
            if baselinePace < 240 {
                calculatedStage = 3
            } else if baselinePace < 300 {
                calculatedStage = 2
            } else if baselinePace < 390 {
                calculatedStage = 1
            } else {
                calculatedStage = 0
            }

            let result = await modelManager.predictRunTypeResult(
                buckets: overlappingWindows,
                paceDelta: currentPace - baselinePace,
                hrDelta: currentHR - baselineHR,
                percentZone4: zone4,
                cadenceDelta: currentCadence - baselineCadence,
                verticalOscillation: validWorkingOsc ?? 9.5,
                runnerStage: calculatedStage,
                cv: cv,
                slope: slope,
                durationMinutes: duration / 60.0,
                cadenceCV: cadenceCV,
                hrCV: hrCV,
                cadenceSlope: cadenceSlope,
                isIndoor: isIndoor,
                isGymKit: isGymKitMachine,
                rawAverageHR: currentHR
            )
            classificationResult = result
            classification = result.targetClass
        } else {
            let framboise = FramboiseEngine()
            let fallbackClass = await framboise.classifyRun(
                buckets: overlappingWindows,
                cv: cv,
                slope: slope,
                zone4: zone4,
                durationMinutes: duration / 60.0,
                cadenceCV: cadenceCV,
                averageHR: currentHR,
                isIndoor: isIndoor
            )
            classification = fallbackClass
            classificationResult = ClassificationResult(
                targetClass: fallbackClass,
                confidence: 0.85,
                probabilities: [fallbackClass: 0.85],
                isReviewRequired: false,
                needsInclineReview: false
            )
        }
        var tags = await engine.generateFramboiseTags(cv: cv, slope: slope, deadStopsCount: buckets.count - trimmed.count, buckets: trimmed, isIndoor: isIndoor)
        if let matchedDrill = matchedDrillIntent {
            WorkoutBridge.markIntentMatched(workoutID: workout.uuid, drillTitle: matchedDrill.drillTitle, workoutDate: workout.startDate)

            if !tags.contains("prescribedDrill") {
                tags.append("prescribedDrill")
            }
            if let preRunId = matchedDrill.preRunDrillId, !tags.contains(preRunId) {
                tags.append(preRunId)
                let drillTag = "drill:\(preRunId)"
                if !tags.contains(drillTag) {
                    tags.append(drillTag)
                }
            }
            let titleTag = "drill:\(matchedDrill.drillTitle)"
            if !tags.contains(titleTag) {
                tags.append(titleTag)
            }
            if let rawTarget = matchedDrill.targetCadence {
                let cleanTarget = PreRunDrill.normalizeCadenceTargetString(rawTarget)
                if !cleanTarget.isEmpty {
                    tags.removeAll { $0.hasPrefix("drillTarget:") }
                    tags.append("drillTarget:\(cleanTarget)")
                }
            }

            // Interval-by-interval drill evaluation
            let drillId = PreRunDrillId(rawValue: matchedDrill.preRunDrillId ?? "")
                ?? PreRunDrillId.allCases.first(where: { $0.title == matchedDrill.drillTitle })
            if let drillId = drillId {
                let thirtyDayCadence = Int(computedBaselineCadence ?? (currentCadence > 0 ? currentCadence : 155))
                let oscDelta = (validWorkingOsc ?? 9.5) - 9.5
                let intervalSummary = DrillIntervalEvaluator.evaluate(
                    workout: workout,
                    buckets: buckets,
                    drillId: drillId,
                    baselineCadence: thirtyDayCadence,
                    workoutDuration: duration,
                    oscDelta: oscDelta,
                    targetCadenceOverride: matchedDrill.targetCadence
                )
                tags.removeAll {
                    $0.hasPrefix("drillIntervals:") ||
                    $0.hasPrefix("drillWorkCadence:") ||
                    $0.hasPrefix("drillRecCadence:") ||
                    $0.hasPrefix("drillReps:") ||
                    $0.hasPrefix("drillRepDetails:")
                }
                for tag in intervalSummary.framboiseTags where !tags.contains(tag) {
                    tags.append(tag)
                }
            }
        }

        let effectiveIsIndoor = (matchedDrillIntent?.isIndoor == true) ? true : isIndoor

        // Build and persist RunSignature for Workout Rhythm and RAG Analyst Chat
        let phaseSegments: [PhaseSegment]
        if let nativeSegments = generatePhaseSegmentsFromActivities(workout: workout, buckets: trimmed) {
            phaseSegments = nativeSegments
        } else {
            phaseSegments = await engine.generatePhaseSegments(from: trimmed, cadenceFloor: 150.0)
        }
        let splits = await engine.calculateSplits(from: trimmed)
        let anomalies: [String] = (cv > 0.12 ? ["High Pace Variability"] : []) + (hrCV > 0.10 ? ["High Cardiac Strain"] : [])
        let signature = RunSignature(
            classification: classification,
            confidence: classificationResult?.confidence ?? 0.85,
            probabilities: classificationResult?.probabilities ?? [classification: 0.85],
            anomalies: anomalies,
            cadenceFloor: 150.0,
            phaseSegments: phaseSegments,
            dataSource: dataSource,
            isIndoor: effectiveIsIndoor,
            needsInclineReview: classificationResult?.needsInclineReview ?? false,
            splits: splits
        )
        let signatureData = try? JSONEncoder().encode(signature)
        let probData = classificationResult.flatMap { try? JSONEncoder().encode($0.probabilities) }
        let weather = WeatherProxyEngine.extractWeatherMetadata(from: workout)

        return RunRecordDTO(
            hkWorkoutID: workout.uuid,
            date: workout.startDate,
            totalDistanceMeters: distance,
            duration: duration,
            rawAvgPace: rawAvgPace,
            rawAvgHeartRate: rawAvgHeartRate,
            rawAvgCadence: rawAvgCadence,
            workingAvgPace: workingPace,
            workingAvgCadence: workingCadence,
            workingAvgHeartRate: workingHR,
            rawAvgVerticalOscillation: finalRawOsc,
            workingAvgVerticalOscillation: validWorkingOsc,
            rawAvgStrideLength: finalRawStride,
            workingAvgStrideLength: validWorkingStride,
            workingDistanceMeters: workingDistance,
            workingDurationSeconds: workingDuration,
            isIndoor: effectiveIsIndoor,
            paceCV: cv,
            paceSlope: slope,
            percentZone4: zone4,
            detectedTypeRaw: classification,
            framboiseTags: tags,
            dataSourceRaw: dataSource,
            classificationConfidence: classificationResult?.confidence,
            classificationProbabilitiesData: probData,
            hrCV: hrCV,
            cadenceSlope: cadenceSlope,
            needsInclineReview: classificationResult?.needsInclineReview,
            runSignatureData: signatureData,
            ambientTemperatureCelsius: weather.temperatureCelsius,
            ambientHumidity: weather.humidityPercent,
            classificationProvenanceRaw: classificationResult?.provenance.rawValue
        )
    }

    private func generatePhaseSegmentsFromActivities(
        workout: HKWorkout,
        buckets: [BucketData]
    ) -> [PhaseSegment]? {
        let activities = workout.workoutActivities.sorted { $0.startDate < $1.startDate }
        guard activities.count >= 4 else { return nil }

        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)

        let workoutStart = workout.startDate

        struct ActivityDraft {
            let startSec: Double
            let endSec: Double
            let duration: Double
            let avgCadence: Double
            let avgPace: Double
            let avgHR: Double
            let isWorkHint: Bool?
        }

        let moving = buckets.filter { $0.meanCadence >= 120 }
        let fallbackCad = moving.isEmpty ? 160.0 : moving.map(\.meanCadence).sorted()[moving.count / 2]
        let validPaces = moving.map(\.meanPaceSecPerKm).filter { $0 > 0 }.sorted()
        let fallbackPace = validPaces.isEmpty ? 300.0 : validPaces[validPaces.count / 2]

        var drafts: [ActivityDraft] = []
        for act in activities {
            guard act.duration > 0 else { continue }
            let startSec = max(0, act.startDate.timeIntervalSince(workoutStart))
            let actEnd = act.endDate ?? act.startDate.addingTimeInterval(act.duration)
            let endSec = max(startSec + 1, actEnd.timeIntervalSince(workoutStart))

            let steps = stepType.flatMap { act.allStatistics[$0]?.sumQuantity()?.doubleValue(for: .count()) } ?? 0
            let distM = distType.flatMap { act.allStatistics[$0]?.sumQuantity()?.doubleValue(for: .meter()) } ?? 0
            let hrVal = hrType.flatMap { act.allStatistics[$0]?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) } ?? 0

            let actBuckets = buckets.filter { $0.startTime >= act.startDate && $0.startTime < actEnd }

            let avgC: Double = {
                if steps > 0 { return steps / (act.duration / 60.0) }
                let cSum = actBuckets.map(\.meanCadence).filter { $0 > 0 }
                return cSum.isEmpty ? fallbackCad : (cSum.reduce(0, +) / Double(cSum.count))
            }()

            let avgP: Double = {
                if distM > 0 { return act.duration / (distM / 1000.0) }
                let pSum = actBuckets.map(\.meanPaceSecPerKm).filter { $0 > 0 }
                return pSum.isEmpty ? fallbackPace : (pSum.reduce(0, +) / Double(pSum.count))
            }()

            let avgH: Double = {
                if hrVal > 0 { return hrVal }
                let hSum = actBuckets.map(\.meanHR).filter { $0 > 0 }
                return hSum.isEmpty ? 0.0 : (hSum.reduce(0, +) / Double(hSum.count))
            }()

            var hint: Bool?
            if let meta = act.metadata {
                for (_, v) in meta {
                    let str = String(describing: v).lowercased()
                    if str.contains("work") || str.contains("push") || str.contains("interval") || str.contains("surge") {
                        hint = true
                        break
                    } else if str.contains("recovery") || str.contains("rest") || str.contains("walk") {
                        hint = false
                        break
                    }
                }
            }

            drafts.append(ActivityDraft(
                startSec: startSec,
                endSec: endSec,
                duration: act.duration,
                avgCadence: avgC,
                avgPace: avgP,
                avgHR: avgH,
                isWorkHint: hint
            ))
        }

        guard drafts.count >= 4 else { return nil }

        // Classify into Warmup, Cooldown, Work, Recovery
        let hasWarmup = drafts[0].duration >= 100.0 || drafts[0].isWorkHint == false
        let hasCooldown = (drafts.last?.duration ?? 0) >= 45.0 || drafts.last?.isWorkHint == false

        let startIndex = hasWarmup ? 1 : 0
        let endIndex = hasCooldown ? (drafts.count - 1) : drafts.count

        guard endIndex > startIndex + 1 else { return nil }

        let middleDrafts = Array(drafts[startIndex..<endIndex])
        let midCads = middleDrafts.map(\.avgCadence).filter { $0 > 0 }.sorted()
        let cadThreshold: Double = {
            guard !midCads.isEmpty else { return fallbackCad }
            let minC = midCads.first ?? fallbackCad
            let maxC = midCads.last ?? fallbackCad
            return (minC + maxC) / 2.0
        }()
        let midPaces = middleDrafts.map(\.avgPace).filter { $0 > 0 }.sorted()
        let paceThreshold: Double = {
            guard !midPaces.isEmpty else { return fallbackPace }
            let minP = midPaces.first ?? fallbackPace
            let maxP = midPaces.last ?? fallbackPace
            return (minP + maxP) / 2.0
        }()

        var segments: [PhaseSegment] = []
        for (i, d) in drafts.enumerated() {
            let kind: String
            if i < startIndex {
                kind = "steady" // Warmup
            } else if i >= endIndex {
                kind = "steady" // Cooldown
            } else if let hint = d.isWorkHint {
                kind = hint ? "work" : "recovery"
            } else {
                let isWork = d.avgCadence >= cadThreshold || (d.avgPace > 0 && d.avgPace <= paceThreshold - 10.0)
                kind = isWork ? "work" : "recovery"
            }

            segments.append(PhaseSegment(
                startSeconds: d.startSec,
                endSeconds: d.endSec,
                kind: kind,
                avgPace: d.avgPace,
                avgCadence: d.avgCadence,
                avgHR: d.avgHR
            ))
        }

        let workCount = segments.filter { $0.kind == "work" }.count
        guard workCount >= 2 else { return nil }
        return segments
    }

    func refreshWorkoutMetrics(for record: RunRecord, in context: ModelContext) async throws {
        guard let workout = try await fetchWorkout(with: record.hkWorkoutID) else {
            throw HKError(.errorNoData)
        }

        // 1. Fetch prior runs for 30-day baseline context
        let targetDate = record.date
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: targetDate) ?? targetDate
        let targetRecordID = record.id
        let descriptor = FetchDescriptor<RunRecord>(
            predicate: #Predicate { $0.date >= thirtyDaysAgo && $0.date < targetDate && $0.id != targetRecordID }
        )
        let priorRecords = (try? context.fetch(descriptor)) ?? []
        let priorRuns = priorRecords.map {
            RunBaselineData(
                date: $0.date,
                pace: $0.workingAvgPace > 0 ? $0.workingAvgPace : $0.rawAvgPace,
                hr: $0.workingAvgHeartRate > 0 ? $0.workingAvgHeartRate : $0.rawAvgHeartRate,
                cadence: $0.workingAvgCadence > 0 ? $0.workingAvgCadence : $0.rawAvgCadence,
                duration: $0.duration,
                isPrescribedDrill: $0.framboiseTags.contains("prescribedDrill")
            )
        }

        // 2. Canonical extraction and bucketing
        let engine = FramboiseEngine()
        let dto: RunRecordDTO
        if let runRecordExtractor = runRecordExtractor {
            dto = try await runRecordExtractor(workout, engine, priorRuns)
        } else {
            dto = try await extractRunRecord(from: workout, engine: engine, priorRuns: priorRuns)
        }

        // 3. Check for existing manual user correction
        let correctionDescriptor = FetchDescriptor<TrainingCorrection>(
            predicate: #Predicate { $0.runRecordID == targetRecordID }
        )
        let hasManualCorrection = (try? context.fetch(correctionDescriptor))?.isEmpty == false

        // 4. Update RunRecord in-place
        let isUserConfirmed = hasManualCorrection || record.classificationProvenance == .userConfirmed || record.framboiseTags.contains("userConfirmedClassification")
        if !isUserConfirmed {
            record.detectedTypeRaw = dto.detectedTypeRaw
            record.classificationConfidence = dto.classificationConfidence
            record.classificationProbabilitiesData = dto.classificationProbabilitiesData
            record.classificationProvenanceRaw = dto.classificationProvenanceRaw
        } else {
            // Guardrail 2: Protect "userConfirmed" state across HealthKit resyncs
            record.classificationProvenance = .userConfirmed
            record.classificationConfidence = 1.0
            if !record.framboiseTags.contains("userConfirmedClassification") {
                record.framboiseTags.append("userConfirmedClassification")
            }
        }
        record.totalDistanceMeters = dto.totalDistanceMeters
        record.duration = dto.duration
        record.rawAvgPace = dto.rawAvgPace
        record.rawAvgHeartRate = dto.rawAvgHeartRate
        record.rawAvgCadence = dto.rawAvgCadence
        record.workingAvgPace = dto.workingAvgPace
        record.workingAvgCadence = dto.workingAvgCadence
        record.workingAvgHeartRate = dto.workingAvgHeartRate
        record.workingDistanceMeters = dto.workingDistanceMeters
        record.workingDurationSeconds = dto.workingDurationSeconds
        if record.framboiseTags.contains("userSetIndoor") {
            record.isIndoor = true
        } else if record.framboiseTags.contains("userSetOutdoor") {
            record.isIndoor = false
        } else {
            record.isIndoor = dto.isIndoor
        }
        record.dataSourceRaw = dto.dataSourceRaw
        if !isUserConfirmed {
            record.classificationConfidence = dto.classificationConfidence
            record.classificationProbabilitiesData = dto.classificationProbabilitiesData
        }
        record.hrCV = dto.hrCV
        record.cadenceSlope = dto.cadenceSlope
        record.needsInclineReview = dto.needsInclineReview
        record.runSignatureData = dto.runSignatureData
        record.rawAvgVerticalOscillation = dto.rawAvgVerticalOscillation
        record.workingAvgVerticalOscillation = dto.workingAvgVerticalOscillation
        record.rawAvgStrideLength = dto.rawAvgStrideLength
        record.workingAvgStrideLength = dto.workingAvgStrideLength
        record.paceCV = dto.paceCV
        record.paceSlope = dto.paceSlope
        record.percentZone4 = dto.percentZone4
        record.ambientTemperatureCelsius = dto.ambientTemperatureCelsius
        record.ambientHumidity = dto.ambientHumidity

        // Preserve user drill & environment intent tags
        var mergedTags = dto.framboiseTags
        for preservedTag in ["userLinkedDrill", "userUnlinkedDrill", "userSetIndoor", "userSetOutdoor"] {
            if record.framboiseTags.contains(preservedTag) && !mergedTags.contains(preservedTag) {
                mergedTags.append(preservedTag)
            }
        }
        if let existingTargetTag = record.framboiseTags.first(where: { $0.hasPrefix("drillTarget:") }),
           !mergedTags.contains(where: { $0.hasPrefix("drillTarget:") }) {
            mergedTags.append(existingTargetTag)
        }
        record.framboiseTags = mergedTags

        try context.save()
    }

    private func fetchAverage(for workout: HKWorkout, type: HKQuantityType, unit: HKUnit) async throws -> Double {
        // 1. Direct workout statistics - exact source used by Apple Fitness
        if let stat = workout.statistics(for: type),
           let avg = stat.averageQuantity()?.doubleValue(for: unit),
           avg > 0 {
            return avg
        }

        // 2. Query HealthStore with object predicate, fallback to date predicate
        let store = healthStore
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(from: workout)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
                if let avg = result?.averageQuantity()?.doubleValue(for: unit), avg > 0 {
                    continuation.resume(returning: avg)
                } else {
                    let datePredicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
                    let fallbackQuery = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: datePredicate, options: .discreteAverage) { _, fallbackResult, _ in
                        let fallbackAvg = fallbackResult?.averageQuantity()?.doubleValue(for: unit) ?? 0.0
                        continuation.resume(returning: fallbackAvg)
                    }
                    store?.execute(fallbackQuery)
                }
            }
            store?.execute(query)
        }
    }

    private func fetchSum(for workout: HKWorkout, type: HKQuantityType, unit: HKUnit) async throws -> Double {
        // 1. Direct workout statistics if available
        if let stat = workout.statistics(for: type),
           let sum = stat.sumQuantity()?.doubleValue(for: unit),
           sum > 0 {
            return sum
        }

        // 2. Query HealthStore
        let store = healthStore
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(from: workout)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                if let sum = result?.sumQuantity()?.doubleValue(for: unit), sum > 0 {
                    continuation.resume(returning: sum)
                } else {
                    let datePredicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
                    let fallbackQuery = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: datePredicate, options: .cumulativeSum) { _, fallbackResult, _ in
                        let fallbackSum = fallbackResult?.sumQuantity()?.doubleValue(for: unit) ?? 0.0
                        continuation.resume(returning: fallbackSum)
                    }
                    store?.execute(fallbackQuery)
                }
            }
            store?.execute(query)
        }
    }
}
