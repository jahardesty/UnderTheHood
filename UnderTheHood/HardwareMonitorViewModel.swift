//
//  HardwareMonitorViewModel.swift
//  UnderTheHood
//
//  Created by Jeff on 8/25/26.
//

import Combine
import Foundation
import IOKit

@MainActor
final class HardwareMonitorViewModel: ObservableObject {
    @Published private(set) var cpuTemp: Double = 0
    @Published private(set) var gpuTemp: Double = 0
    @Published private(set) var fanRPM: Double = 0
    @Published private(set) var fanSpeedAvailable = false
    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var chipModel: String = ""
    @Published private(set) var hasBattery: Bool = false
    @Published private(set) var batteryCycleCount: Int = 0
    @Published private(set) var batteryHealth: String = ""

    private let sensorReader: SystemSensorReader?
    private var refreshTask: Task<Void, Never>?

    init(sensorReader: SystemSensorReader? = SystemSensorReader()) {
        self.sensorReader = sensorReader
        // Defer method calls that use self until after initialization completes
        Task { @MainActor [weak self] in
            self?.refreshMetrics()
            self?.startRefreshing()
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    func refreshMetrics() {
        guard let sensorReader else {
            cpuTemp = 0
            gpuTemp = 0
            fanRPM = 0
            fanSpeedAvailable = false
            cpuUsage = 0
            chipModel = ""
            batteryCycleCount = 0
            batteryHealth = ""
            return
        }
        
        let snapshot = sensorReader.fetchCurrentMetrics()
        cpuTemp = snapshot.cpuTempMax
        gpuTemp = snapshot.gpuTempMax
        fanRPM = snapshot.fanSpeedRPM
        fanSpeedAvailable = snapshot.fanSpeedAvailable
        cpuUsage = snapshot.cpuUsage
        chipModel = withUnsafePointer(to: snapshot.chipModel) {
            $0.withMemoryRebound(to: CChar.self, capacity: 64) {
                String(cString: $0)
            }
        }
        hasBattery = snapshot.batteryPresent
        if snapshot.batteryPresent {
            // If your snapshot includes these fields, assign them; otherwise defaults remain
            batteryCycleCount = Int(snapshot.batteryCycleCount)
            batteryHealth = withUnsafePointer(to: snapshot.batteryHealth) {
                $0.withMemoryRebound(to: CChar.self, capacity: 64) {
                    String(cString: $0)
                }
            }
        } else {
            batteryCycleCount = 0
            batteryHealth = ""
        }
        
    }

    private func startRefreshing() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self?.refreshMetrics()
            }
        }
    }
}

