//
//  UnderTheHoodApp.swift
//  UnderTheHood
//
//  Created by Jeff on 8/25/26.
//

import SwiftUI

@main
struct UnderTheHoodApp: App {
    @StateObject private var viewModel = HardwareMonitorViewModel()
    
    var body: some Scene {
        MenuBarExtra {
            SensorPopoverView(viewModel: viewModel)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                Text(viewModel.cpuTemp > 0 ? String(format: "%.0f°C", viewModel.cpuTemp) : "--°C")
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)
        }
    }
