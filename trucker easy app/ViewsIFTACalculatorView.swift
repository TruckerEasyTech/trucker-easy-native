//
//  IFTACalculatorView.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
//

import SwiftUI
import SwiftData

struct IFTACalculatorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var fuelPurchases: [FuelPurchase]
    @Query private var trips: [Trip]
    
    @State private var selectedQuarter = 1
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var stateBreakdowns: [StateBreakdown] = []
    @State private var isCalculating = false
    
    let quarters = ["Q1 (Jan-Mar)", "Q2 (Apr-Jun)", "Q3 (Jul-Sep)", "Q4 (Oct-Dec)"]
    let years = Array((Calendar.current.component(.year, from: Date()) - 5)...Calendar.current.component(.year, from: Date()))
    
    var quarterDates: (start: Date, end: Date) {
        let calendar = Calendar.current
        let startMonth = (selectedQuarter - 1) * 3 + 1
        let startComponents = DateComponents(year: selectedYear, month: startMonth, day: 1)
        guard let start = calendar.date(from: startComponents),
              let end = calendar.date(byAdding: DateComponents(month: 3, day: -1), to: start)
        else { return (Date(), Date()) }
        return (start, end)
    }
    
    var filteredFuelPurchases: [FuelPurchase] {
        fuelPurchases.filter { purchase in
            purchase.date >= quarterDates.start && purchase.date <= quarterDates.end
        }
    }
    
    var filteredTrips: [Trip] {
        trips.filter { trip in
            trip.startDate >= quarterDates.start && trip.startDate <= quarterDates.end
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Select Quarter") {
                    Picker("Quarter", selection: $selectedQuarter) {
                        ForEach(1...4, id: \.self) { quarter in
                            Text(quarters[quarter - 1]).tag(quarter)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Picker("Year", selection: $selectedYear) {
                        ForEach(years, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    
                    LabeledContent("Period") {
                        Text("\(quarterDates.start, format: .dateTime.month().day()) - \(quarterDates.end, format: .dateTime.month().day())")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Summary") {
                    LabeledContent("Fuel Purchases", value: "\(filteredFuelPurchases.count)")
                    LabeledContent("Trips", value: "\(filteredTrips.count)")
                    
                    if !stateBreakdowns.isEmpty {
                        LabeledContent("States", value: "\(stateBreakdowns.count)")
                    }
                }
                
                if !stateBreakdowns.isEmpty {
                    Section("State Breakdown") {
                        ForEach(stateBreakdowns) { breakdown in
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
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .leading) {
                                        Text("Gallons")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(String(format: "%.2f", breakdown.gallons))
                                            .font(.subheadline)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing) {
                                        Text("Cost")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(String(format: "$%.2f", breakdown.fuelCost))
                                            .font(.subheadline)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    Section("Totals") {
                        LabeledContent("Total Miles") {
                            Text(String(format: "%.1f", stateBreakdowns.reduce(0) { $0 + $1.miles }))
                                .fontWeight(.semibold)
                        }
                        
                        LabeledContent("Total Gallons") {
                            Text(String(format: "%.2f", stateBreakdowns.reduce(0) { $0 + $1.gallons }))
                                .fontWeight(.semibold)
                        }
                        
                        LabeledContent("Total Fuel Cost") {
                            Text(String(format: "$%.2f", stateBreakdowns.reduce(0) { $0 + $1.fuelCost }))
                                .fontWeight(.semibold)
                        }
                        
                        let totalMiles = stateBreakdowns.reduce(0) { $0 + $1.miles }
                        let totalGallons = stateBreakdowns.reduce(0) { $0 + $1.gallons }
                        LabeledContent("Average MPG") {
                            Text(String(format: "%.2f", totalGallons > 0 ? totalMiles / totalGallons : 0))
                                .fontWeight(.semibold)
                        }
                    }
                }
                
                Section {
                    Button(action: calculateReport) {
                        HStack {
                            Spacer()
                            if isCalculating {
                                ProgressView()
                            } else {
                                Text(stateBreakdowns.isEmpty ? "Calculate Report" : "Recalculate")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isCalculating || filteredFuelPurchases.isEmpty)
                    
                    if !stateBreakdowns.isEmpty {
                        Button(action: saveReport) {
                            HStack {
                                Spacer()
                                Text("Save Report")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("IFTA Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func calculateReport() {
        isCalculating = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Group fuel purchases by state
            let grouped = Dictionary(grouping: filteredFuelPurchases, by: { $0.state })
            
            stateBreakdowns = grouped.map { state, purchases in
                let totalGallons = purchases.reduce(0) { $0 + $1.gallons }
                let totalCost = purchases.reduce(0) { $0 + $1.totalCost }
                
                // Estimate miles per state based on fuel consumption
                // This is a simplified calculation - in real app, you'd track actual miles per state
                let totalMiles = filteredTrips.reduce(0) { $0 + $1.totalMiles }
                let totalAllGallons = filteredFuelPurchases.reduce(0) { $0 + $1.gallons }
                let stateMiles = totalAllGallons > 0 ? (totalGallons / totalAllGallons) * totalMiles : 0
                
                return StateBreakdown(
                    state: state,
                    miles: stateMiles,
                    gallons: totalGallons,
                    fuelCost: totalCost
                )
            }.sorted { $0.state < $1.state }
            
            isCalculating = false
        }
    }
    
    private func saveReport() {
        let totalMiles = stateBreakdowns.reduce(0) { $0 + $1.miles }
        let totalGallons = stateBreakdowns.reduce(0) { $0 + $1.gallons }
        let totalCost = stateBreakdowns.reduce(0) { $0 + $1.fuelCost }
        
        let report = IFTAReport(
            quarterStartDate: quarterDates.start,
            quarterEndDate: quarterDates.end,
            totalMiles: totalMiles,
            totalGallons: totalGallons,
            totalFuelCost: totalCost
        )
        
        // Save state breakdown as JSON
        if let jsonData = try? JSONEncoder().encode(stateBreakdowns) {
            report.stateBreakdownData = jsonData
        }
        
        modelContext.insert(report)
        dismiss()
    }
}

#Preview {
    IFTACalculatorView()
        .modelContainer(for: [FuelPurchase.self, Trip.self, IFTAReport.self], inMemory: true)
}
