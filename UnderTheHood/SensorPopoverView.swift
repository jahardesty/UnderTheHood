//
//  SensorPopoverView.swift
//  UnderTheHood
//
//  Created by Jeff on 8/25/26.
//

import SwiftUI

struct SensorPopoverView: View {
    @ObservedObject var viewModel: HardwareMonitorViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Under The Hood")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Divider()
            
            MetricRow(
                icon: "cpu",
                label: "CPU Temp",
                value: String(format: "%.1f °C", viewModel.cpuTemp),
                color: temperatureColor(viewModel.cpuTemp)
            )
            
            MetricRow(
                icon: "gauge",
                label: "CPU Usage",
                value: String(format: "%.1f%%", viewModel.cpuUsage),
                color: .accentColor
            )
            
            MetricRow(
                icon: "gpu",
                label: "GPU Temp",
                value: String(format: "%.1f °C", viewModel.gpuTemp),
                color: temperatureColor(viewModel.gpuTemp)
            )
            
            MetricRow(
                icon: "fanblades",
                label: "Fan Speed",
                value: fanSpeedText,
                color: .blue
            )
            
            Divider()
            
            HStack {
                Spacer()
                Button("Quit UnderTheHood") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .frame(width: 220)
    }
    
    private func temperatureColor(_ temp: Double) -> Color {
        switch temp {
        case ..<65: return .green
        case 65..<85: return .orange
        default: return .red
        }
    }

    private var fanSpeedText: String {
        guard viewModel.fanSpeedAvailable else {
            return "Unavailable"
        }

        return viewModel.fanRPM > 0 ? String(format: "%.0f RPM", viewModel.fanRPM) : "Stopped"
    }
}

struct MetricRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            Text(label)
                .font(.body)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.bold)
        }
    }
}

