//
//  HardwareMonitorViewModel.swift
//  UnderTheHood
//
//  Created by Jeff on 8/25/26.
//

import Combine
import Foundation

@MainActor
final class HardwareMonitorViewModel: ObservableObject {
    @Published private(set) var cpuTemp: Double = 0
    @Published private(set) var gpuTemp: Double = 0
    @Published private(set) var fanRPM: Double = 0
    @Published private(set) var fanSpeedAvailable = false

    private let sensorReader: SystemSensorReader?
    private var refreshTask: Task<Void, Never>?

    init(sensorReader: SystemSensorReader? = SystemSensorReader()) {
        self.sensorReader = sensorReader
        refreshMetrics()
        startRefreshing()
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
            return
        }

        let snapshot = sensorReader.fetchCurrentMetrics()
        cpuTemp = snapshot.cpuTempMax
        gpuTemp = snapshot.gpuTempMax
        fanRPM = snapshot.fanSpeedRPM
        fanSpeedAvailable = snapshot.fanSpeedAvailable
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
