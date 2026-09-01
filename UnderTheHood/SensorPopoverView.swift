//
//  SensorPopoverView.swift
//  UnderTheHood
//
//  Created by Jeff on 8/25/26.
//

import SwiftUI

struct SensorPopoverView: View {
    @ObservedObject var viewModel: HardwareMonitorViewModel
    @Environment(\.openWindow) private var openWindow // 1. Inject openWindow
    @State private var isHoveringQuit = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Under The Hood")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            
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
                icon: "cpu.fill",
                label: "GPU Temp",
                value: String(format: "%.1f °C", viewModel.gpuTemp),
                color: temperatureColor(viewModel.gpuTemp)
            )
            
            VStack(alignment: .leading, spacing: 8) {
                MetricRow(
                    icon: "memorychip",
                    label: "Memory",
                    value: String(format: "%.1f / %.1f GB", viewModel.memoryUsageGB, viewModel.memoryTotalGB),
                    color: viewModel.memoryPercentage > 85 ? .orange : .purple
                )
                
                // Optional: Progress bar indicator
                Gauge(value: viewModel.memoryPercentage, in: 0...100) {
                    EmptyView()
                } currentValueLabel: {
                    Text(String(format: "%.0f%%", viewModel.memoryPercentage))
                        .font(.caption2)
                }
                .gaugeStyle(.accessoryLinear)
                .tint(viewModel.memoryPercentage > 85 ? .orange : .purple)
            }
            
            Divider()
            
            // MARK: BATTERY
            if viewModel.hasBattery {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Battery")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    MetricRow(
                        icon: "battery.100percent",
                        label: "Cycle Count",
                        value: String(viewModel.batteryCycleCount),
                        color: .green
                    )
                    MetricRow(
                        icon: "heart.circle",
                        label: "Health",
                        value: viewModel.batteryHealth.isEmpty ? "—" : viewModel.batteryHealth,
                        color: .blue
                    )
                    
                    // 2. Add "More Details" Button
                    Button(action: {
                        openWindow(id: "battery-details")
                        NSApp.activate(ignoringOtherApps: true) // Brings new window to front
                    }) {
                        HStack {
                            Text("More Details")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            
            Divider()
            
            MetricRow(
                icon: "macpro.gen1.fill",
                label: "Model",
                value: viewModel.chipModel,
                color: .white
            )
            
            Divider()
            
            HStack {
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    ZStack {
                        Text("Quit")
                            .opacity(isHoveringQuit ? 0 : 1)
                        Image(systemName: "xmark.square")
                            .opacity(isHoveringQuit ? 1 : 0)
                            .font(.system(size: 18))
                    }
                    .frame(width: 40, height: 20)
                }
                .onHover { hovering in
                    isHoveringQuit = hovering
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

