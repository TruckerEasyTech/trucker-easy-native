//
//  TripDetailView.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
//

import SwiftUI
import SwiftData

struct TripDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var trip: Trip
    @State private var showingAddFuel = false
    @State private var showingAddExpense = false
    @State private var showingEndTrip = false
    
    var body: some View {
        List {
            Section("Trip Details") {
                LabeledContent("Start Date", value: trip.startDate, format: .dateTime)
                LabeledContent("Start Location", value: trip.startLocation)
                
                if let endDate = trip.endDate {
                    LabeledContent("End Date", value: endDate, format: .dateTime)
                }
                
                if let endLocation = trip.endLocation {
                    LabeledContent("End Location", value: endLocation)
                }
                
                LabeledContent("Start Odometer", value: String(format: "%.1f", trip.startOdometer))
                
                if let endOdometer = trip.endOdometer {
                    LabeledContent("End Odometer", value: String(format: "%.1f", endOdometer))
                }
                
                LabeledContent("Total Miles", value: String(format: "%.1f", trip.totalMiles))
                
                if !trip.truckNumber.isEmpty {
                    LabeledContent("Truck Number", value: trip.truckNumber)
                }
                
                if trip.isActive {
                    HStack {
                        Spacer()
                        Button("End Trip") {
                            showingEndTrip = true
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                }
            }
            
            Section {
                LabeledContent("Total Fuel Cost", value: String(format: "$%.2f", trip.totalFuelCost))
                LabeledContent("Total Expenses", value: String(format: "$%.2f", trip.totalExpenses))
            } header: {
                Text("Summary")
            }
            
            Section {
                ForEach(trip.fuelPurchases.sorted(by: { $0.date > $1.date })) { fuel in
                    NavigationLink(destination: FuelPurchaseDetailView(fuelPurchase: fuel)) {
                        FuelPurchaseRow(fuelPurchase: fuel)
                    }
                }
                .onDelete(perform: deleteFuelPurchases)
                
                Button(action: { showingAddFuel = true }) {
                    Label("Add Fuel Purchase", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Fuel Purchases (\(trip.fuelPurchases.count))")
            }
            
            Section {
                ForEach(trip.expenses.sorted(by: { $0.date > $1.date })) { expense in
                    NavigationLink(destination: ExpenseDetailView(expense: expense)) {
                        ExpenseRow(expense: expense)
                    }
                }
                .onDelete(perform: deleteExpenses)
                
                Button(action: { showingAddExpense = true }) {
                    Label("Add Expense", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Expenses (\(trip.expenses.count))")
            }
            
            if !trip.notes.isEmpty {
                Section("Notes") {
                    Text(trip.notes)
                }
            }
        }
        .navigationTitle("Trip Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddFuel) {
            AddFuelPurchaseView(trip: trip)
        }
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView(trip: trip)
        }
        .sheet(isPresented: $showingEndTrip) {
            EndTripView(trip: trip)
        }
    }
    
    private func deleteFuelPurchases(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let sorted = trip.fuelPurchases.sorted(by: { $0.date > $1.date })
                modelContext.delete(sorted[index])
            }
        }
    }
    
    private func deleteExpenses(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let sorted = trip.expenses.sorted(by: { $0.date > $1.date })
                modelContext.delete(sorted[index])
            }
        }
    }
}

struct FuelPurchaseRow: View {
    let fuelPurchase: FuelPurchase
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(fuelPurchase.location)
                    .font(.headline)
                Spacer()
                Text(String(format: "$%.2f", fuelPurchase.totalCost))
                    .font(.headline)
            }
            
            HStack {
                Text(fuelPurchase.state)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Text(String(format: "%.2f gal @ $%.3f", fuelPurchase.gallons, fuelPurchase.pricePerGallon))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(fuelPurchase.date, format: .dateTime.month().day())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ExpenseRow: View {
    let expense: Expense
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(expense.category.rawValue)
                    .font(.headline)
                Spacer()
                Text(String(format: "$%.2f", expense.amount))
                    .font(.headline)
            }
            
            HStack {
                if !expense.vendorName.isEmpty {
                    Text(expense.vendorName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !expense.location.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary)
                    }
                }
                
                if !expense.location.isEmpty {
                    Text(expense.location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(expense.date, format: .dateTime.month().day())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct EndTripView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var trip: Trip
    
    @State private var endDate = Date()
    @State private var endLocation = ""
    @State private var endOdometer = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("End Trip") {
                    DatePicker("End Date", selection: $endDate)
                    
                    TextField("End Location", text: $endLocation)
                        .autocapitalization(.words)
                    
                    TextField("Ending Odometer", text: $endOdometer)
                        .keyboardType(.decimalPad)
                }
                
                Section("Trip Summary") {
                    if let odometerValue = Double(endOdometer), odometerValue > trip.startOdometer {
                        LabeledContent("Total Miles", value: String(format: "%.1f", odometerValue - trip.startOdometer))
                    }
                    LabeledContent("Fuel Purchases", value: "\(trip.fuelPurchases.count)")
                    LabeledContent("Total Fuel Cost", value: String(format: "$%.2f", trip.totalFuelCost))
                    LabeledContent("Other Expenses", value: "\(trip.expenses.count)")
                }
            }
            .navigationTitle("End Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Complete") {
                        endTrip()
                    }
                    .disabled(endLocation.isEmpty || endOdometer.isEmpty)
                }
            }
        }
    }
    
    private func endTrip() {
        trip.endDate = endDate
        trip.endLocation = endLocation
        trip.endOdometer = Double(endOdometer)
        trip.isActive = false
        dismiss()
    }
}

#Preview {
    NavigationStack {
        TripDetailView(trip: Trip(startLocation: "Chicago, IL", startOdometer: 10000, truckNumber: "T-123"))
    }
    .modelContainer(for: Trip.self, inMemory: true)
}
