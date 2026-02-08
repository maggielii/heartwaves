import HealthKit

final class HealthKitManager {
    private let store = HKHealthStore()

    func requestAuthorization(completion: @escaping (Bool, String) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, "Health data not available on this device")
            return
        }

        guard
            let steps = HKObjectType.quantityType(forIdentifier: .stepCount),
            let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
            let activeenergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            let heartrate = HKObjectType.quantityType(forIdentifier: .heartRate),
            let rheartrate = HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            let sleepAnalysis = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
            let envAudio = HKObjectType.quantityType(forIdentifier: .environmentalAudioExposure),
            let headphoneAudio = HKObjectType.quantityType(forIdentifier: .headphoneAudioExposure),
            let exerciseType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime)

        else {
            completion(false, "StepCount type not available")
            return
        }
    
        

        store.requestAuthorization(toShare: [], read: [steps, distance, activeenergy, heartrate, rheartrate, sleepAnalysis, envAudio, headphoneAudio, exerciseType]) { success, error in
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
    
    /// may change options to discrete max/min depending on what looking for
    func fetchTodayDiscrete(id: HKQuantityTypeIdentifier, unit: HKUnit, completion: @escaping (Double, String?) -> Void) {
        guard let fetchType = HKQuantityType.quantityType(forIdentifier: id) else {
            completion(0, "Type not available")
            return
        }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: fetchType,
                                      quantitySamplePredicate: predicate,
                                      options: .discreteAverage) { _, result, error in
            let average = result?.averageQuantity()?.doubleValue(for: unit) ?? 0
            DispatchQueue.main.async {
                completion(average, error?.localizedDescription)
            }
        }

        store.execute(query)
    }
    
    
    
    func fetchSamples(id: HKQuantityTypeIdentifier,
                      unit: HKUnit,
                      startDate: Date,
                      endDate: Date,
                      completion: @escaping ([HealthDataPoint], String?) -> Void) {
        
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: id) else {
            completion([], "Type not available")
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        let query = HKSampleQuery(sampleType: quantityType,
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
            
            guard let samples = samples as? [HKQuantitySample] else {
                DispatchQueue.main.async {
                    completion([], error?.localizedDescription)
                }
                return
            }
            
            let dataPoints = samples.map { sample in
                HealthDataPoint(
                    date: sample.startDate,
                    value: sample.quantity.doubleValue(for: unit)
                )
            }
            
            DispatchQueue.main.async {
                completion(dataPoints, nil)
            }
        }
        
        store.execute(query)
    }
    
    
    func fetchDailyQuantity(
        id: HKQuantityTypeIdentifier,
        unit: HKUnit,
        startDate: Date,
        endDate: Date,
        options: HKStatisticsOptions,
        completion: @escaping ([HealthDataPoint], String?) -> Void
    ) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: id) else {
            completion([], "Type not available")
            return
        }

        let calendar = Calendar.current
        let anchorDate = calendar.startOfDay(for: startDate)
        var interval = DateComponents()
        interval.day = 1

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        let query = HKStatisticsCollectionQuery(
            quantityType: quantityType,
            quantitySamplePredicate: predicate,
            options: options,
            anchorDate: anchorDate,
            intervalComponents: interval
        )

        query.initialResultsHandler = { _, results, error in
            if let error = error {
                DispatchQueue.main.async { completion([], error.localizedDescription) }
                return
            }

            var points: [HealthDataPoint] = []
            results?.enumerateStatistics(from: startDate, to: endDate) { stat, _ in
                let value: Double
                switch options {
                case .cumulativeSum:
                    value = stat.sumQuantity()?.doubleValue(for: unit) ?? 0
                case .discreteAverage:
                    value = stat.averageQuantity()?.doubleValue(for: unit) ?? 0
                case .discreteMin:
                    value = stat.minimumQuantity()?.doubleValue(for: unit) ?? 0
                case .discreteMax:
                    value = stat.maximumQuantity()?.doubleValue(for: unit) ?? 0
                default:
                    value = stat.averageQuantity()?.doubleValue(for: unit) ?? 0
                }

                points.append(HealthDataPoint(date: stat.startDate, value: value))
            }

            DispatchQueue.main.async {
                completion(points.sorted { $0.date < $1.date }, nil)
            }
        }

        store.execute(query)
    }

    
    
    
    func fetchSleepData(startDate: Date, endDate: Date, completion: @escaping ([SleepDataPoint], String?) -> Void) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion([], "Sleep type not available")
            return
        }

        // Widen the range so overnight sleep that starts before startDate is still included
        let cal = Calendar.current
        let widenedStart = cal.date(byAdding: .day, value: -1, to: startDate) ?? startDate
        let widenedEnd   = cal.date(byAdding: .day, value:  1, to: endDate) ?? endDate

       
        let predicate = HKQuery.predicateForSamples(withStart: widenedStart, end: widenedEnd, options: [])

        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { _, samples, error in

            if let error = error {
                DispatchQueue.main.async {
                    completion([], error.localizedDescription)
                }
                return
            }

            let catSamples = (samples as? [HKCategorySample]) ?? []
            for s in catSamples {
                let dt = s.endDate.timeIntervalSince(s.startDate)
                print("sleep:", s.startDate, "->", s.endDate, "seconds:", dt, "raw:", s.value)
            }


    
            print("HK sleep samples fetched:", catSamples.count)
            if let first = catSamples.first {
                print("First sample:", first.startDate, "->", first.endDate, "raw:", first.value)
            }

            let sleepData: [SleepDataPoint] = catSamples.compactMap { sample in
                guard let v = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
                return SleepDataPoint(
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    value: v
                )
            }

            DispatchQueue.main.async {
                completion(sleepData, nil)
            }
        }

        store.execute(query)
    }

    
    func fillMissingDays(points: [HealthDataPoint], startDate: Date, endDate: Date) -> [HealthDataPoint] {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: startDate)
        let endDay = cal.startOfDay(for: endDate)

        var map: [Date: Double] = [:]
        for p in points {
            map[cal.startOfDay(for: p.date)] = p.value
        }

        var out: [HealthDataPoint] = []
        var d = startDay
        while d < endDay {
            out.append(HealthDataPoint(date: d, value: map[d] ?? 0))
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return out
    }

}
