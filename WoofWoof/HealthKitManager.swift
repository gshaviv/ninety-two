
import Foundation
import HealthKit
import WoofKit

enum HealthKitManagerError: Error {
    case notAvailable
    case notPermitted
}

class HealthKitManager {
    static private(set) var lastDate: Date? = nil
    static let healthKitDataStore = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    static let shared = HKHealthStore.isHealthDataAvailable() ? HealthKitManager() : nil
    class var isAvailable: Bool {
        return HKHealthStore.isHealthDataAvailable()
    }

    class func authorize(_ result: @escaping (Bool) -> Void) {
        guard let glucoseQuantity = HKQuantityType.quantityType(forIdentifier: .bloodGlucose),
        let insulingDelivery = HKQuantityType.quantityType(forIdentifier: .insulinDelivery) else {
            result(false)
            return
        }
        healthKitDataStore?.requestAuthorization(toShare: [glucoseQuantity, insulingDelivery], read: [glucoseQuantity, insulingDelivery], completion: {(success,error) in
            result(success)
        })
    }

    class var isAuthorized: Bool {
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return false
        }
        return healthKitDataStore?.authorizationStatus(for: glucoseType) == .sharingAuthorized
    }

    class func getAuthorizationState(_ complete: @escaping (Bool) -> Void) {
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose), let insulingDelivery = HKQuantityType.quantityType(forIdentifier: .insulinDelivery) else {
            complete(false)
            return
        }
        healthKitDataStore?.getRequestStatusForAuthorization(toShare: [glucoseType, insulingDelivery], read: [glucoseType, insulingDelivery]) { (status, err) in
            if let _ = err {
                complete(false)
            } else {
                complete(status == .unnecessary)
            }
        }
    }

    func write(records: [Entry]) {
        guard let insulinType = HKQuantityType.quantityType(forIdentifier: .insulinDelivery) else {
            return
        }
        let data = records.compactMap { (r:Entry) -> HKQuantitySample? in
            guard r.bolus > 0 else {
                return nil
            }
            return HKQuantitySample(type: insulinType,
                             quantity: HKQuantity(unit: HKUnit.internationalUnit(), doubleValue: Double(r.bolus)),
                             start: r.date,
                             end: r.date,
                             metadata: [HKMetadataKeyInsulinDeliveryReason: HKInsulinDeliveryReason.bolus.rawValue])
        }
        HealthKitManager.healthKitDataStore?.save(data) { (success, error) in
            //print("Glucose data saved to HealthKit.")
        }
    }
    
    func write(points: [GlucosePoint])  {
        let glucoseMassUnit = HKUnit(from: "mg/dL")
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return
        }
        let glucoseData = points.map {
            HKQuantitySample(type: glucoseType,
                             quantity: HKQuantity(unit: glucoseMassUnit, doubleValue: $0.value),
                             start: $0.date,
                             end: $0.date,
                             metadata: nil)
        }
        HealthKitManager.healthKitDataStore?.save(glucoseData) { (success, error) in
            HealthKitManager.lastDate = glucoseData.last?.endDate
        }
    }
    
    func findLast(completion: @escaping (Date?) -> ()) {
        if let last =  HealthKitManager.lastDate {
            completion(last)
            return
        }
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            fatalError("*** Unable to create glucose quantity type***")
        }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: glucoseType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { (query, results, error) in
            guard let result = results?.first as? HKQuantitySample else {
                if let error = error {
                    logError("HK error \(error)")
                } else {
                    log("No HK records")
                }
                completion(nil)
                return
            }
            
            HealthKitManager.lastDate = result.endDate
            completion(result.endDate)
        }
        HealthKitManager.healthKitDataStore?.execute(query)
    }
}





