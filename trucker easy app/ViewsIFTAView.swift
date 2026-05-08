//
//  IFTAView.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
//

import SwiftUI
import SwiftData
import Charts

struct IFTAView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \IFTAReport.quarterStartDate, order: .reverse) private var reports: [IFTAReport]
    @Query private var fuelPurchases: [FuelPurchase]
    @Query private var trips: [Trip]
    
    @State private var showingCalculator = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: { showingCalculator = true }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("IFTA Calculator", systemImage: "calculator")
                                    .font(.headline)
                                
                                Text("Calculate quarterly tax report")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                Section("Quick Stats") {
                    CurrentQuarterStatsView(fuelPurchases: fuelPurchases, trips: trips)
                }
                
                if !reports.isEmpty {
                    Section("Past Reports") {
                        ForEach(reports) { report in
                            NavigationLink(destination: IFTAReportDetailView(report: report)) {
                                IFTAReportRow(report: report)
                            }
                        }
                        .onDelete(perform: deleteReports)
                    }
                }
            }
            .navigationTitle("IFTA")
            .sheet(isPresented: $showingCalculator) {
                IFTACalculatorView()
            }
            .overlay {
                if reports.isEmpty && fuelPurchases.isEmpty {
                    ContentUnavailableView(
                        "No IFTA Data",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text("Start tracking fuel purchases to generate IFTA reports")
                    )
                }
            }
        }
    }
    
    private func deleteReports(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(reports[index])
            }
        }
    }
}

struct CurrentQuarterStatsView: View {
    let fuelPurchases: [FuelPurchase]
    let trips: [Trip]
    
    var quarterDates: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        
        let quarterMonth = ((month - 1) / 3) * 3 + 1
        let startComponents = DateComponents(year: year, month: quarterMonth, day: 1)
        let start = calendar.date(from: startComponents)!
        let end = calendar.date(byAdding: DateComponents(month: 3, day: -1), to: start)!
        
        return (start, end)
    }
    
    var quarterFuelPurchases: [FuelPurchase] {
        fuelPurchases.filter { purchase in
            purchase.date >= quarterDates.start && purchase.date <= quarterDates.end
        }
    }
    
    var quarterTrips: [Trip] {
        trips.filter { trip in
            trip.startDate >= quarterDates.start && trip.startDate <= quarterDates.end
        }
    }
    
    var totalMiles: Double {
        quarterTrips.reduce(0) { $0 + $1.totalMiles }
    }
    
    var totalGallons: Double {
        quarterFuelPurchases.reduce(0) { $0 + $1.gallons }
    }
    
    var totalFuelCost: Double {
        quarterFuelPurchases.reduce(0) { $0 + $1.totalCost }
    }
    
    var averageMPG: Double {
        guard totalGallons > 0 else { return 0 }
        return totalMiles / totalGallons
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Quarter")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("\(quarterDates.start, format: .dateTime.month().day()) - \(quarterDates.end, format: .dateTime.month().day())")
                .font(.subheadline)
                .fontWeight(.medium)
            
            Divider()
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Total Miles")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0f", totalMiles))
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Gallons")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f", totalGallons))
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Fuel Cost")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "$%.2f", totalFuelCost))
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Avg MPG")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f", averageMPG))
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct IFTAReportRow: View {
    let report: IFTAReport
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Q\(quarterNumber(for: report.quarterStartDate))")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                Text("\(report.quarterStartDate, format: .dateTime.year())")
                    .font(.headline)
                
                Spacer()
                
                Text(report.generatedDate, format: .dateTime.month().day())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Miles")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0f", report.totalMiles))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                VStack(alignment: .leading) {
                    Text("Gallons")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f", report.totalGallons))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                VStack(alignment: .leading) {
                    Text("MPG")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f", report.averageMPG))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func quarterNumber(for date: Date) -> Int {
        let month = Calendar.current.component(.month, from: date)
        return (month - 1) / 3 + 1
    }
}

#Preview {
    IFTAView()
        .modelContainer(for: [IFTAReport.self, FuelPurchase.self, Trip.self], inMemory: true)
}
