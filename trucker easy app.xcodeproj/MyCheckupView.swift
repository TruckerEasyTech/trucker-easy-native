//
//  MyCheckupView.swift
//  Trucker Easy
//
//  Tab 2: Health & Wellness
//  Features: Daily mood check (5 stars), medication reminders, food suggestions
//

import SwiftUI

struct MyCheckupView: View {
    @StateObject private var viewModel = CheckupViewModel()
    @State private var selectedStars = 0
    @State private var showMedicationSheet = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Daily mood check
                    VStack(spacing: 16) {
                        Text("How are you feeling today?")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        HStack(spacing: 20) {
                            ForEach(1...5, id: \.self) { star in
                                Button {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedStars = star
                                        viewModel.saveMoodRating(star)
                                    }
                                } label: {
                                    Image(systemName: star <= selectedStars ? "star.fill" : "star")
                                        .font(.system(size: 44))
                                        .foregroundColor(star <= selectedStars ? .yellow : .gray)
                                        .scaleEffect(star == selectedStars ? 1.2 : 1.0)
                                }
                            }
                        }
                        .padding()
                        
                        if selectedStars > 0 {
                            Text(getMoodMessage(for: selectedStars))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .transition(.opacity)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                    .padding(.horizontal)
                    
                    // Medication reminders
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "pills.fill")
                                .font(.title2)
                                .foregroundColor(Color("TruckerOrange"))
                            
                            Text("Medication Reminders")
                                .font(.title3)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Button {
                                showMedicationSheet = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(Color("TruckerOrange"))
                            }
                        }
                        
                        if viewModel.medications.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                Text("No reminders set")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("Tap + to add your first reminder")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        } else {
                            ForEach(viewModel.medications) { medication in
                                MedicationCard(
                                    medication: medication,
                                    onTaken: { viewModel.markAsTaken(medication) },
                                    onDelete: { viewModel.deleteMedication(medication) }
                                )
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                    .padding(.horizontal)
                    
                    // Food suggestions (geofencing-based)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "fork.knife.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                            
                            Text("Healthy Eating")
                                .font(.title3)
                                .fontWeight(.bold)
                        }
                        
                        Text("We'll notify you 15 min before rest stops with meal suggestions based on your health profile.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Recent suggestions
                        if !viewModel.recentSuggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Recent Suggestions")
                                    .font(.headline)
                                    .padding(.top, 8)
                                
                                ForEach(viewModel.recentSuggestions) { suggestion in
                                    FoodSuggestionCard(suggestion: suggestion)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("My Check-up")
            .sheet(isPresented: $showMedicationSheet) {
                AddMedicationSheet { medication in
                    viewModel.addMedication(medication)
                }
            }
        }
        .onAppear {
            selectedStars = viewModel.todaysMoodRating
        }
    }
    
    private func getMoodMessage(for stars: Int) -> String {
        switch stars {
        case 1: return "Sorry you're having a tough day, driver. Stay safe out there."
        case 2: return "Hang in there. Better miles ahead."
        case 3: return "Doing okay. Keep rolling."
        case 4: return "Good day on the road!"
        case 5: return "Excellent! Keep that energy rolling!"
        default: return ""
        }
    }
}

// MARK: - Medication Card
struct MedicationCard: View {
    let medication: Medication
    let onTaken: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(medication.name)
                    .font(.headline)
                
                HStack(spacing: 12) {
                    Label(medication.timeFormatted, systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let lastTaken = medication.lastTaken {
                        Label("Last: \(lastTaken.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            
            Spacer()
            
            Button {
                onTaken()
            } label: {
                Text("Took It")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Food Suggestion Card
struct FoodSuggestionCard: View {
    let suggestion: FoodSuggestion
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.green)
                Text(suggestion.locationName)
                    .font(.headline)
            }
            
            Text(suggestion.recommendation)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if !suggestion.avoidItems.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("Avoid: \(suggestion.avoidItems.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Add Medication Sheet
struct AddMedicationSheet: View {
    @Environment(\.dismiss) var dismiss
    var onAdd: (Medication) -> Void
    
    @State private var medicationName = ""
    @State private var selectedTime = Date()
    @State private var repeatDaily = true
    
    var body: some View {
        NavigationView {
            Form {
                Section("Medication Details") {
                    TextField("Medication Name", text: $medicationName)
                    
                    DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    
                    Toggle("Repeat Daily", isOn: $repeatDaily)
                }
                
                Section {
                    Button("Save Reminder") {
                        let medication = Medication(
                            name: medicationName,
                            time: selectedTime,
                            repeatDaily: repeatDaily
                        )
                        onAdd(medication)
                        dismiss()
                    }
                    .disabled(medicationName.isEmpty)
                }
            }
            .navigationTitle("Add Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    MyCheckupView()
}
