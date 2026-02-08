import HealthKit

final class HealthKitManager {
    private let store = HKHealthStore()

    func requestAuthorization(completion: @escaping (Bool, String) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, "Health data not available on this device")
            return
        }

        guard let steps = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            completion(false, "StepCount type not available")
            return
        }
        guard let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else {
            completion(false, "Distance type not available")
            return
        }
        guard let activeenergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            completion(false, "activeEnergyBurned type not available")
            return
        }

        store.requestAuthorization(toShare: [], read: [steps, distance, activeenergy]) { success, error in
            DispatchQueue.main.async {
                completion(success, error?.localizedDescription ?? "OK")
            }
        }
    }

    func fetchTodayGeneral(id: HKQuantityTypeIdentifier, unit: HKUnit, completion: @escaping (Double, String?) -> Void) {
        guard let fetchType = HKQuantityType.quantityType(forIdentifier: id) else {
            completion(0, "Type not available")
            return
        }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: fetchType,
                                      quantitySamplePredicate: predicate,
                                      options: .cumulativeSum) { _, result, error in
            let sum = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
            DispatchQueue.main.async {
                completion(sum, error?.localizedDescription)
            }
        }

        store.execute(query)
    }
}
