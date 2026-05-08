// HealthKitManager.swift
// Lightweight helper to handle HealthKit authorization

import Foundation
import HealthKit

final class HealthKitManager {
    static let shared = HealthKitManager()
    private let healthStore = HKHealthStore()

    private init() {}

    func requestAuthorization() {
        // Check availability first
        guard HKHealthStore.isHealthDataAvailable() else {
            #if DEBUG
            print("HealthKit not available on this device.")
            #endif
            return
        }

        // Define the data types to read (Steps, Sleep)
        var readTypes = Set<HKObjectType>()
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            readTypes.insert(steps)
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            readTypes.insert(sleep)
        }

        healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
            #if DEBUG
            if success {
                print("HealthKit authorization granted.")
            } else {
                print("HealthKit authorization denied or error: \(error?.localizedDescription ?? "unknown")")
            }
            #endif
        }
    }
}
