import Foundation
import HealthKit
@testable import Runalyst

final class MockHealthStore: @unchecked Sendable, HKHealthStoreProtocol {
    var requestAuthorizationCalled = false
    var requestedTypesToShare: Set<HKSampleType>?
    var requestedTypesToRead: Set<HKObjectType>?
    var requestAuthorizationError: Error?

    var authorizationStatusCalled = false
    var authorizationStatusToReturn: HKAuthorizationStatus = .notDetermined

    var statusForAuthorizationRequestToReturn: HKAuthorizationRequestStatus = .shouldRequest

    var enableBackgroundDeliveryCalled = false
    var enabledBackgroundDeliveryType: HKObjectType?
    var enableBackgroundDeliveryError: Error?

    var executeQueryCalled = false

    func requestAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws {
        requestAuthorizationCalled = true
        requestedTypesToShare = typesToShare
        requestedTypesToRead = typesToRead

        if let error = requestAuthorizationError {
            throw error
        }
    }

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        authorizationStatusCalled = true
        return authorizationStatusToReturn
    }

    func statusForAuthorizationRequest(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws -> HKAuthorizationRequestStatus {
        return statusForAuthorizationRequestToReturn
    }

    func enableBackgroundDelivery(for type: HKObjectType, frequency: HKUpdateFrequency) async throws {
        enableBackgroundDeliveryCalled = true
        enabledBackgroundDeliveryType = type

        if let error = enableBackgroundDeliveryError {
            throw error
        }
    }

    func execute(_ query: HKQuery) {
        executeQueryCalled = true
    }
}
