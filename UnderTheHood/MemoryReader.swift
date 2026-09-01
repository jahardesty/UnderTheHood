//
//  MemoryReader.swift
//  UnderTheHood
//
//  Created by Jeffrey Hardesty on 9/1/26.
//

import Foundation
import MachO

struct MemoryMetrics {
    let usedGB: Double
    let totalGB: Double
    let usagePercentage: Double
    
    var formattedString: String {
        return String(format: "%.1f / %.1f GB (%.0f%%)", usedGB, totalGB, usagePercentage)
    }
}

enum MemoryReader {
    static func fetchMetrics() -> MemoryMetrics {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalGB = Double(totalBytes) / 1_073_741_824.0
        
        guard result == KERN_SUCCESS else {
            return MemoryMetrics(usedGB: 0, totalGB: totalGB, usagePercentage: 0)
        }
        
        let pageSize = UInt64(vm_kernel_page_size)
        
        // Active + Inactive + Speculative + Wired memory = Used Memory
        let activeBytes = UInt64(stats.active_count) * pageSize
        let inactiveBytes = UInt64(stats.inactive_count) * pageSize
        let speculativeBytes = UInt64(stats.speculative_count) * pageSize
        let wiredBytes = UInt64(stats.wire_count) * pageSize
        let compressedBytes = UInt64(stats.compressor_page_count) * pageSize
        
        // Pure memory currently occupied by applications and system kernel
        let usedBytes = activeBytes + inactiveBytes + speculativeBytes + wiredBytes + compressedBytes
        let usedGB = Double(usedBytes) / 1_073_741_824.0
        let percentage = (usedGB / totalGB) * 100.0
        
        return MemoryMetrics(
            usedGB: usedGB,
            totalGB: totalGB,
            usagePercentage: min(percentage, 100.0)
        )
    }
}
