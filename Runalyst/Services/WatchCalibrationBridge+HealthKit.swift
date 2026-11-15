import Foundation
import HealthKit

extension WatchCalibrationBridge {
    /// Refreshes athlete age and 30-day resting heart rate samples asynchronously from HealthKit if authorized.
    func refreshHealthKitCalibrationStatsIfNeeded() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()

        if let dob = try? store.dateOfBirthComponents(),
           let dobDate = Calendar.current.date(from: dob) {
            let age = Calendar.current.dateComponents([.year], from: dobDate, to: Date()).year ?? 0
            if age > 0 {
                UserDefaults.standard.set(age, forKey: "runnerAge")
            }
        }

        guard let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return }
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: Date(), options: .strictStartDate)
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        let samples: [Double] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: rhrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, results, _ in
                let values = (results as? [HKQuantitySample])?.map {
                    $0.quantity.doubleValue(for: bpmUnit)
                } ?? []
                continuation.resume(returning: values)
            }
            store.execute(query)
        }

        if !samples.isEmpty {
            UserDefaults.standard.set(samples, forKey: "cachedRestingHRSamples")
        }
    }
}
