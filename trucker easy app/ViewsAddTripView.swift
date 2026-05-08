//
//  AddTripView.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
//

import SwiftUI
import SwiftData

struct AddTripView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var startDate = Date()
    @State private var startLocation = ""
    @State private var startOdometer = ""
    @State private var truckNumber = ""
    @State private var notes = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Trip Information") {
                    DatePicker("Start Date", selection: $startDate)
                    
                    TextField("Start Location", text: $startLocation)
                        .autocapitalization(.words)
                    
                    TextField("Starting Odometer", text: $startOdometer)
                        .keyboardType(.decimalPad)
                    
                    TextField("Truck Number", text: $truckNumber)
                        .textInputAutocapitalization(.characters)
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTrip()
                    }
                    .disabled(startLocation.isEmpty || startOdometer.isEmpty)
                }
            }
        }
    }
    
    private func saveTrip() {
        let trip = Trip(
            startDate: startDate,
            startLocation: startLocation,
            startOdometer: Double(startOdometer) ?? 0,
            truckNumber: truckNumber,
            notes: notes
        )
        
        modelContext.insert(trip)
        dismiss()
    }
}

#Preview {
    AddTripView()
        .modelContainer(for: Trip.self, inMemory: true)
}
