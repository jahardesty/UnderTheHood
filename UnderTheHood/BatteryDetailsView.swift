//
//  BatteryDetailsView.swift
//  UnderTheHood
//
//  Created by Jeffrey Hardesty on 8/31/26.
//

//
//  BatteryDetailsView.swift
//  UnderTheHood
//

import SwiftUI

struct BatteryDetailsView: View {
    @ObservedObject var viewModel: HardwareMonitorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if viewModel.hasBattery, let rawInfo = viewModel.fetchRawBatteryInfo() {
                    Group {
                        // MARK: Health & Degradation
                        Section("Health & Degradation") {
                            detailRow(
                                label: "Condition",
                                value: viewModel.batteryHealth.isEmpty ? "Normal" : viewModel.batteryHealth
                            )
                            
                            detailRow(
                                label: "Health Ratio",
                                value: String(format: "%.1f%%", rawInfo.calculatedHealthPercentage),
                                valueColor: rawInfo.calculatedHealthPercentage > 80 ? .green : .orange
                            )
                            
                            detailRow(
                                label: "Cycle Count",
                                value: "\(viewModel.batteryCycleCount)"
                            )
                        }
                        
                        // MARK: Raw Capacity Stats
                        Section("Raw Capacity") {
                            detailRow(
                                label: "Current Charge",
                                value: "\(rawInfo.currentCapacitymAh) mAh"
                            )
                            
                            detailRow(
                                label: "Maximum Charge",
                                value: "\(rawInfo.maxCapacitymAh) mAh"
                            )
                            
                            detailRow(
                                label: "Design Capacity",
                                value: "\(rawInfo.designCapacitymAh) mAh"
                            )
                        }
                        
                        // MARK: Electrical Readouts
                        Section("Power & Diagnostics") {
                            detailRow(
                                label: "Voltage",
                                value: String(format: "%.2f V", rawInfo.voltageVolts)
                            )
                            
                            detailRow(
                                label: "Amperage",
                                value: String(format: "%.2f A", rawInfo.amperageAmps)
                            )
                            
                            if rawInfo.temperatureCelsius > 0 {
                                detailRow(
                                    label: "Battery Temp",
                                    value: String(format: "%.1f °C", rawInfo.temperatureCelsius)
                                )
                            }
                        }
                    }
                } else {
                    Section {
                        Text("No battery detected.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Bottom bar
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }

    private func detailRow(label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.primary)
            
            Spacer()

            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(valueColor)
        }
    }
}
