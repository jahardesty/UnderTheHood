//
//  HardwareMonitorViewBattery.swift
//  UnderTheHood
//
//  Created by Jeffrey Hardesty on 8/31/26.
//

import Foundation
import IOKit

extension HardwareMonitorViewModel {
    struct RawBatteryInfo {
        var currentCapacitymAh: Int = 0
        var maxCapacitymAh: Int = 0
        var designCapacitymAh: Int = 0
        var voltageVolts: Double = 0.0
        var amperageAmps: Double = 0.0
        var temperatureCelsius: Double = 0.0
        var isCharging: Bool = false
        
        var calculatedHealthPercentage: Double {
            guard designCapacitymAh > 0 else { return 0.0 }
            return (Double(maxCapacitymAh) / Double(designCapacitymAh)) * 100.0
        }
    }
    
    func fetchRawBatteryInfo() -> RawBatteryInfo? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let propDict = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        
        var info = RawBatteryInfo()
        
        info.currentCapacitymAh = propDict["AppleRawCurrentCapacity"] as? Int ?? propDict["CurrentCapacity"] as? Int ?? 0
        info.maxCapacitymAh = propDict["AppleRawMaxCapacity"] as? Int ?? propDict["MaxCapacity"] as? Int ?? 0
        info.designCapacitymAh = propDict["DesignCapacity"] as? Int ?? 0
        
        if let mV = propDict["Voltage"] as? Double {
            info.voltageVolts = mV / 1000.0
        }
        
        if let mA = propDict["Amperage"] as? Double {
            info.amperageAmps = mA / 1000.0
        }
        
        if let temp = propDict["Temperature"] as? Double {
            info.temperatureCelsius = temp / 100.0
        }
        
        info.isCharging = propDict["IsCharging"] as? Bool ?? false
        
        return info
    }
}
