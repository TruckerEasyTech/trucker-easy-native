//import SwiftUI
import SwiftData // <--- ADICIONE ESTA LINHA EXATAMENTE AQUI
//  AddFuelPurchaseView.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
import SwiftUI
import SwiftData
import PhotosUI

struct AddFuelPurchaseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var trip: Trip? = nil
    
    @State private var date = Date()
    @State private var location = ""
    @State private var state = ""
    @State private var gallons = ""
    @State private var pricePerGallon = ""
    @State private var odometer = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var receiptImage: Data?
    
    let usStates = ["AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
                    "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
                    "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
                    "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
                    "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"]
    
    var totalCost: Double {
        let gal = Double(gallons) ?? 0
        let price = Double(pricePerGallon) ?? 0
        return gal * price
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Purchase Information") {
                    DatePicker("Date", selection: $date)
                    
                    TextField("Location", text: $location)
                        .autocapitalization(.words)
                    
                    Picker("State", selection: $state) {
                        Text("Select State").tag("")
                        ForEach(usStates, id: \.self) { state in
                            Text(state).tag(state)
                        }
                    }
                    
                    TextField("Odometer Reading", text: $odometer)
                        .keyboardType(.decimalPad)
                }
                
                Section("Fuel Details") {
                    TextField("Gallons", text: $gallons)
                        .keyboardType(.decimalPad)
                    
                    TextField("Price per Gallon", text: $pricePerGallon)
                        .keyboardType(.decimalPad)
                    
                    if !gallons.isEmpty && !pricePerGallon.isEmpty {
                        LabeledContent("Total Cost") {
                            Text(String(format: "$%.2f", totalCost))
                                .fontWeight(.semibold)
                        }
                    }
                }
                
                Section("Receipt") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        if let receiptImage = receiptImage,
                           let uiImage = UIImage(data: receiptImage) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                        } else {
                            Label("Add Receipt Photo", systemImage: "camera")
                        }
                    }
                }
            }
            .navigationTitle("Fuel Purchase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveFuelPurchase()
                    }
                    .disabled(location.isEmpty || state.isEmpty || gallons.isEmpty || pricePerGallon.isEmpty)
                }
            }
            .onChange(of: selectedPhoto) { oldValue, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                        receiptImage = data
                    }
                }
            }
        }
    }
    
    private func saveFuelPurchase() {
        let purchase = FuelPurchase(
            date: date,
            location: location,
            state: state,
            gallons: Double(gallons) ?? 0,
            pricePerGallon: Double(pricePerGallon) ?? 0,
            odometer: Double(odometer) ?? 0
        )
        
        purchase.receiptImageData = receiptImage
        purchase.trip = trip
        
        modelContext.insert(purchase)
        dismiss()
    }
}

#Preview {
    AddFuelPurchaseView()
        .modelContainer(for: FuelPurchase.self, inMemory: true)
}
