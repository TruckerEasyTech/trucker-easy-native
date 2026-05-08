//
//  AddExpenseView.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
//

import SwiftUI
import SwiftData
import PhotosUI

struct AddExpenseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var trip: Trip? = nil
    
    @State private var date = Date()
    @State private var category = ExpenseCategory.other
    @State private var amount = ""
    @State private var vendorName = ""
    @State private var location = ""
    @State private var notes = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var receiptImage: Data?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Expense Details") {
                    DatePicker("Date", selection: $date)
                    
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    
                    TextField("Vendor Name", text: $vendorName)
                        .autocapitalization(.words)
                    
                    TextField("Location", text: $location)
                        .autocapitalization(.words)
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
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("New Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveExpense()
                    }
                    .disabled(amount.isEmpty)
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
    
    private func saveExpense() {
        let expense = Expense(
            date: date,
            category: category,
            amount: Double(amount) ?? 0,
            vendorName: vendorName,
            notes: notes,
            location: location
        )
        
        expense.receiptImageData = receiptImage
        expense.trip = trip
        
        modelContext.insert(expense)
        dismiss()
    }
}

#Preview {
    AddExpenseView()
        .modelContainer(for: Expense.self, inMemory: true)
}
