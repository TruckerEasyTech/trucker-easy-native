//import SwiftData
//  IFTAReportDetailView.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
//

import SwiftUI
import SwiftData
import Charts

struct IFTAReportDetailView: View {
    let report: IFTAReport
    
    var stateBreakdowns: [StateBreakdown] {
        guard let data = report.stateBreakdownData,
              let breakdowns = try? JSONDecoder().decode([StateBreakdown].self, from: data) else {
            return []
        }
        return breakdowns
    }
    
    private func quarterNumber(for date: Date) -> Int {
        let month = Calendar.current.component(.month, from: date)
        return (month - 1) / 3 + 1
    }
    
    var body: some View {
        List {
            Section("Report Summary") {
                LabeledContent("Quarter") {
                    Text("Q\(quarterNumber(for: report.quarterStartDate)) \(report.quarterStartDate, format: .dateTime.year())")
                }
                
                LabeledContent("Period") {
                    Text("\(report.quarterStartDate, format: .dateTime.month().day()) - \(report.quarterEndDate, format: .dateTime.month().day())")
                }
                
                LabeledContent("Generated", value: report.generatedDate, format: .dateTime)
            }
            
            Section("Totals") {
                LabeledContent("Total Miles") {
                    Text(String(format: "%.1f", report.totalMiles))
                        .fontWeight(.semibold)
                }
                
                LabeledContent("Total Gallons") {
                    Text(String(format: "%.2f", report.totalGallons))
                        .fontWeight(.semibold)
                }
                
                LabeledContent("Total Fuel Cost") {
                    Text(String(format: "$%.2f", report.totalFuelCost))
                        .fontWeight(.semibold)
                }
                
                LabeledContent("Average MPG") {
                    Text(String(format: "%.2f", report.averageMPG))
                        .fontWeight(.semibold)
                }
            }
            
            if !stateBreakdowns.isEmpty {
                Section("Mileage by State") {
                    Chart(stateBreakdowns.sorted { $0.miles > $1.miles }.prefix(10)) { breakdown in
                        BarMark(
                            x: .value("Miles", breakdown.miles),
                            y: .value("State", breakdown.state)
                        )
                        .foregroundStyle(by: .value("State", breakdown.state))
                    }
                    .frame(height: 300)
                    .padding(.vertical)
                }
                
                Section("State Details") {
                    ForEach(stateBreakdowns.sorted { $0.state < $1.state }) { breakdown in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(breakdown.state)
                                .font(.headline)
                            
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Miles")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.1f", breakdown.miles))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .leading) {
                                    Text("Gallons")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.2f", breakdown.gallons))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing) {
                                    Text("Cost")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "$%.2f", breakdown.fuelCost))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing) {
                                    Text("MPG")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.2f", breakdown.averageMPG))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("IFTA Report")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        IFTAReportDetailView(report: IFTAReport(
            quarterStartDate: Date(),
            quarterEndDate: Date().addingTimeInterval(90 * 24 * 60 * 60),
            totalMiles: 15000,
            totalGallons: 2500,
            totalFuelCost: 9750
        ))
    }
    .modelContainer(for: IFTAReport.self, inMemory: true)
}
