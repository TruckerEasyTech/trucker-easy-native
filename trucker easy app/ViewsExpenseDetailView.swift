import SwiftUI
import SwiftData // <--- ADICIONE ESTA LINHA EXATAMENTE AQUI//import SwiftData
//  ExpenseDetailView.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
import SwiftUI

struct ExpenseDetailView: View {
    @Bindable var expense: Expense
    
    var body: some View {
        List {
            Section("Details") {
                LabeledContent("Date", value: expense.date, format: .dateTime)
                LabeledContent("Category", value: expense.category.rawValue)
                LabeledContent("Amount", value: String(format: "$%.2f", expense.amount))
                
                if !expense.vendorName.isEmpty {
                    LabeledContent("Vendor", value: expense.vendorName)
                }
                
                if !expense.location.isEmpty {
                    LabeledContent("Location", value: expense.location)
                }
            }
            
            if let receiptData = expense.receiptImageData,
               let uiImage = UIImage(data: receiptData) {
                Section("Receipt") {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                }
            }
            
            if !expense.notes.isEmpty {
                Section("Notes") {
                    Text(expense.notes)
                }
            }
            
            if let trip = expense.trip {
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
        .navigationTitle("Expense")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ExpenseDetailView(expense: Expense(category: .fuel, amount: 125.50, vendorName: "Shell"))
    }
    .modelContainer(for: Expense.self, inMemory: true)
}
