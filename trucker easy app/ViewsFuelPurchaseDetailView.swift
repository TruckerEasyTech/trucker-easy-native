//import SwiftData
import SwiftUI
import SwiftData // <--- ADICIONE ESTA LINHA AQUI
//  FuelPurchaseDetailView.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
//

import SwiftUI

struct FuelPurchaseDetailView: View {
    @Bindable var fuelPurchase: FuelPurchase
    
    var body: some View {
        List {
            Section("Purchase Details") {
                LabeledContent("Date", value: fuelPurchase.date, format: .dateTime)
                LabeledContent("Location", value: fuelPurchase.location)
                LabeledContent("State", value: fuelPurchase.state)
                LabeledContent("Odometer", value: String(format: "%.1f", fuelPurchase.odometer))
            }
            
            Section("Fuel Information") {
                LabeledContent("Gallons", value: String(format: "%.2f", fuelPurchase.gallons))
                LabeledContent("Price per Gallon", value: String(format: "$%.3f", fuelPurchase.pricePerGallon))
                LabeledContent("Total Cost") {
                    Text(String(format: "$%.2f", fuelPurchase.totalCost))
                        .fontWeight(.semibold)
                }
            }
            
            if let receiptData = fuelPurchase.receiptImageData,
               let uiImage = UIImage(data: receiptData) {
                Section("Receipt") {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                }
            }
            
            if let trip = fuelPurchase.trip {
                Section("Trip") {
                    NavigationLink(destination: TripDetailView(trip: trip)) {
                        VStack(alignment: .leading) {
                            Text(trip.startLocation)
                                .font(.headline)
                            if let endLocation = trip.endLocation {
                                Text("→ \(endLocation)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Fuel Purchase")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        FuelPurchaseDetailView(fuelPurchase: FuelPurchase(location: "Pilot Travel Center", state: "IL", gallons: 120.5, pricePerGallon: 3.899))
    }
    .modelContainer(for: FuelPurchase.self, inMemory: true)
}
