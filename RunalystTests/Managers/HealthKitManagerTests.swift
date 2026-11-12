import XCTest
import HealthKit
import SwiftData
@testable import Runalyst

@MainActor
final class HealthKitManagerTests: XCTestCase {

    var mockStore: MockHealthStore!
    var sut: HealthKitManager!

    override func setUp() async throws {
        mockStore = MockHealthStore()
    }

    override func tearDown() async throws {
        mockStore = nil
        sut = nil
    }

    func testRequestAuthorization_WhenHealthDataNotAvailable_ThrowsError() async {
        // Arrange
        sut = HealthKitManager(healthStore: mockStore, isHealthDataAvailable: { false })

        // Act & Assert
        do {
            try await sut.requestAuthorization()
            XCTFail("Expected error to be thrown")
        } catch {
            let hkError = error as? HKError
            XCTAssertEqual(hkError?.code, .errorHealthDataUnavailable)
        }

        XCTAssertFalse(mockStore.requestAuthorizationCalled)
    }

    func testRequestAuthorization_WhenAvailable_RequestsTypesAndUpdatesStatus() async throws {
        // Arrange
        sut = HealthKitManager(healthStore: mockStore, isHealthDataAvailable: { true })
        mockStore.authorizationStatusToReturn = .sharingAuthorized

        // Act
        try await sut.requestAuthorization()

        // Assert
        XCTAssertTrue(mockStore.requestAuthorizationCalled)
        XCTAssertEqual(mockStore.requestedTypesToShare?.isEmpty, true)

        let readTypes = try XCTUnwrap(mockStore.requestedTypesToRead)
        XCTAssertTrue(readTypes.contains(HKObjectType.workoutType()))
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            XCTAssertTrue(readTypes.contains(hrType))
        }

        XCTAssertTrue(mockStore.authorizationStatusCalled)
        XCTAssertTrue(mockStore.enableBackgroundDeliveryCalled)
        XCTAssertEqual(mockStore.enabledBackgroundDeliveryType, HKObjectType.workoutType())

        XCTAssertTrue(sut.isAuthorized)
    }

    func testRequestAuthorization_WhenAuthorizationFails_ThrowsError() async {
        // Arrange
        sut = HealthKitManager(healthStore: mockStore, isHealthDataAvailable: { true })
        let expectedError = NSError(domain: "Test", code: 1, userInfo: nil)
        mockStore.requestAuthorizationError = expectedError

        // Act & Assert
        do {
            try await sut.requestAuthorization()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual(error as NSError, expectedError)
        }

        XCTAssertFalse(mockStore.authorizationStatusCalled)
        XCTAssertFalse(mockStore.enableBackgroundDeliveryCalled)
    }

    func testRequestAuthorizationIfNeeded_WhenUnnecessary_DoesNotCallRequestAuthorization() async throws {
        // Arrange
        sut = HealthKitManager(healthStore: mockStore, isHealthDataAvailable: { true })
        mockStore.statusForAuthorizationRequestToReturn = .unnecessary

        // Act
        try await sut.requestAuthorizationIfNeeded()

        // Assert
        XCTAssertFalse(mockStore.requestAuthorizationCalled)
        XCTAssertTrue(sut.isAuthorized)
        XCTAssertTrue(mockStore.enableBackgroundDeliveryCalled)
    }

    func testRequestAuthorizationIfNeeded_WhenShouldRequest_CallsRequestAuthorization() async throws {
        // Arrange
        sut = HealthKitManager(healthStore: mockStore, isHealthDataAvailable: { true })
        mockStore.statusForAuthorizationRequestToReturn = .shouldRequest

        // Act
        try await sut.requestAuthorizationIfNeeded()

        // Assert
        XCTAssertTrue(mockStore.requestAuthorizationCalled)
    }

    func testRefreshWorkoutMetrics_WhenWorkoutNotFound_ThrowsNoData() async throws {
        // Arrange
        sut = HealthKitManager(healthStore: mockStore, isHealthDataAvailable: { true })
        sut.workoutFetcher = { _ in nil }

        let schema = Schema([RunRecord.self, CoachingInsight.self, DrillRecommendation.self, TrainingCorrection.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let record = RunRecord(
            hkWorkoutID: UUID(),
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1800,
            rawAvgPace: 360,
            rawAvgHeartRate: 150,
            rawAvgCadence: 160,
            workingAvgPace: 360,
            workingAvgCadence: 160,
            workingAvgHeartRate: 150,
            paceCV: 0.05,
            paceSlope: 0.01,
            percentZone4: 0.1,
            detectedTypeRaw: "Easy Run"
        )
        context.insert(record)
        try context.save()

        // Act & Assert
        do {
            try await sut.refreshWorkoutMetrics(for: record, in: context)
            XCTFail("Expected HKError.errorNoData to be thrown")
        } catch let hkError as HKError {
            XCTAssertEqual(hkError.code, .errorNoData)
        }
    }

    func testRefreshWorkoutMetrics_WhenWorkoutExists_UpdatesScalarsAndClassification() async throws {
        // Arrange
        sut = HealthKitManager(healthStore: mockStore, isHealthDataAvailable: { true })
        let workoutUUID = UUID()
        let sampleWorkout = HKWorkout(
            activityType: .running,
            start: Date().addingTimeInterval(-1800),
            end: Date(),
            duration: 1800,
            totalEnergyBurned: nil,
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 5000),
            metadata: nil
        )
        sut.workoutFetcher = { _ in sampleWorkout }

        let updatedDTO = RunRecordDTO(
            hkWorkoutID: workoutUUID,
            date: Date(),
            totalDistanceMeters: 5100,
            duration: 1800,
            rawAvgPace: 350,
            rawAvgHeartRate: 155,
            rawAvgCadence: 168,
            workingAvgPace: 348,
            workingAvgCadence: 170,
            workingAvgHeartRate: 156,
            rawAvgVerticalOscillation: 8.5,
            workingAvgVerticalOscillation: 8.4,
            rawAvgStrideLength: 1.22,
            workingAvgStrideLength: 1.25,
            workingDistanceMeters: 5050,
            workingDurationSeconds: 1780,
            isIndoor: false,
            paceCV: 0.04,
            paceSlope: 0.005,
            percentZone4: 0.15,
            detectedTypeRaw: "Tempo Run",
            framboiseTags: ["urbanTraffic"]
        )
        sut.runRecordExtractor = { _, _, _ in updatedDTO }

        let schema = Schema([RunRecord.self, CoachingInsight.self, DrillRecommendation.self, TrainingCorrection.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let record = RunRecord(
            hkWorkoutID: workoutUUID,
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1800,
            rawAvgPace: 360,
            rawAvgHeartRate: 150,
            rawAvgCadence: 160,
            workingAvgPace: 360,
            workingAvgCadence: 160,
            workingAvgHeartRate: 150,
            paceCV: 0.05,
            paceSlope: 0.01,
            percentZone4: 0.1,
            detectedTypeRaw: "Easy Run"
        )
        context.insert(record)
        try context.save()

        // Act
        try await sut.refreshWorkoutMetrics(for: record, in: context)

        // Assert
        XCTAssertEqual(record.detectedTypeRaw, "Tempo Run")
        XCTAssertEqual(record.workingAvgStrideLength, 1.25)
        XCTAssertEqual(record.rawAvgStrideLength, 1.22)
        XCTAssertEqual(record.workingAvgCadence, 170)
        XCTAssertEqual(record.workingAvgVerticalOscillation, 8.4)
        XCTAssertEqual(record.workingAvgPace, 348)
        XCTAssertTrue(record.framboiseTags.contains("urbanTraffic"))
    }

    func testRefreshWorkoutMetrics_PreservesManualCorrection() async throws {
        // Arrange
        sut = HealthKitManager(healthStore: mockStore, isHealthDataAvailable: { true })
        let workoutUUID = UUID()
        let sampleWorkout = HKWorkout(
            activityType: .running,
            start: Date().addingTimeInterval(-1800),
            end: Date(),
            duration: 1800,
            totalEnergyBurned: nil,
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 5000),
            metadata: nil
        )
        sut.workoutFetcher = { _ in sampleWorkout }

        let updatedDTO = RunRecordDTO(
            hkWorkoutID: workoutUUID,
            date: Date(),
            totalDistanceMeters: 5100,
            duration: 1800,
            rawAvgPace: 350,
            rawAvgHeartRate: 155,
            rawAvgCadence: 168,
            workingAvgPace: 348,
            workingAvgCadence: 170,
            workingAvgHeartRate: 156,
            rawAvgVerticalOscillation: 8.5,
            workingAvgVerticalOscillation: 8.4,
            rawAvgStrideLength: 1.22,
            workingAvgStrideLength: 1.25,
            workingDistanceMeters: 5050,
            workingDurationSeconds: 1780,
            isIndoor: false,
            paceCV: 0.04,
            paceSlope: 0.005,
            percentZone4: 0.15,
            detectedTypeRaw: "Intervals",
            framboiseTags: []
        )
        sut.runRecordExtractor = { _, _, _ in updatedDTO }

        let schema = Schema([RunRecord.self, CoachingInsight.self, DrillRecommendation.self, TrainingCorrection.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let record = RunRecord(
            hkWorkoutID: workoutUUID,
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1800,
            rawAvgPace: 360,
            rawAvgHeartRate: 150,
            rawAvgCadence: 160,
            workingAvgPace: 360,
            workingAvgCadence: 160,
            workingAvgHeartRate: 150,
            paceCV: 0.05,
            paceSlope: 0.01,
            percentZone4: 0.1,
            detectedTypeRaw: "Steady Effort"
        )
        context.insert(record)

        // Insert manual TrainingCorrection for this run
        let correction = TrainingCorrection(
            runRecordID: record.id,
            originalLabel: "Easy Run",
            correctedLabel: "Steady Effort",
            featureVector: [360, 0.05, 0.01, 0.1, 30.0]
        )
        context.insert(correction)
        try context.save()

        // Act
        try await sut.refreshWorkoutMetrics(for: record, in: context)

        // Assert - manual correction remains "Steady Effort" even though DTO had "Intervals"
        XCTAssertEqual(record.detectedTypeRaw, "Steady Effort")
        XCTAssertEqual(record.workingAvgStrideLength, 1.25)
    }

    func testRefreshWorkoutMetrics_PreservesUserLinkedDrillTags() async throws {
        // Arrange
        sut = HealthKitManager(healthStore: mockStore, isHealthDataAvailable: { true })
        let workoutUUID = UUID()
        let sampleWorkout = HKWorkout(
            activityType: .running,
            start: Date().addingTimeInterval(-1800),
            end: Date(),
            duration: 1800,
            totalEnergyBurned: nil,
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 5000),
            metadata: nil
        )
        sut.workoutFetcher = { _ in sampleWorkout }

        let updatedDTO = RunRecordDTO(
            hkWorkoutID: workoutUUID,
            date: Date(),
            totalDistanceMeters: 5100,
            duration: 1800,
            rawAvgPace: 350,
            rawAvgHeartRate: 155,
            rawAvgCadence: 168,
            workingAvgPace: 348,
            workingAvgCadence: 170,
            workingAvgHeartRate: 156,
            rawAvgVerticalOscillation: 8.5,
            workingAvgVerticalOscillation: 8.4,
            rawAvgStrideLength: 1.22,
            workingAvgStrideLength: 1.25,
            workingDistanceMeters: 5050,
            workingDurationSeconds: 1780,
            isIndoor: false,
            paceCV: 0.04,
            paceSlope: 0.005,
            percentZone4: 0.15,
            detectedTypeRaw: "Tempo Run",
            framboiseTags: ["prescribedDrill"]
        )
        sut.runRecordExtractor = { _, _, _ in updatedDTO }

        let schema = Schema([RunRecord.self, CoachingInsight.self, DrillRecommendation.self, TrainingCorrection.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let record = RunRecord(
            hkWorkoutID: workoutUUID,
            date: Date(),
            totalDistanceMeters: 5000,
            duration: 1800,
            rawAvgPace: 360,
            rawAvgHeartRate: 150,
            rawAvgCadence: 160,
            workingAvgPace: 360,
            workingAvgCadence: 160,
            workingAvgHeartRate: 150,
            paceCV: 0.05,
            paceSlope: 0.01,
            percentZone4: 0.1,
            detectedTypeRaw: "Easy Run",
            framboiseTags: ["userLinkedDrill", "drill:Strides"]
        )
        context.insert(record)
        try context.save()

        // Act
        try await sut.refreshWorkoutMetrics(for: record, in: context)

        // Assert
        XCTAssertTrue(record.framboiseTags.contains("userLinkedDrill"))
        XCTAssertTrue(record.framboiseTags.contains("prescribedDrill"))
    }
}
