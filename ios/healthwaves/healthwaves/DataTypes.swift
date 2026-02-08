//
//  DataTypes.swift
//  healthwaves
//
//  Created by Sophia Xu on 2026-02-07.
//

import Foundation
import HealthKit

struct HealthDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct SleepDataPoint: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let value: HKCategoryValueSleepAnalysis  // The sleep stage
    
    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
    
    var durationInHours: Double {
        duration / 3600
    }
}





