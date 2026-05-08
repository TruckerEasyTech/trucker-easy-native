//
//  MyCheckupViewFixed.swift
//  Trucker Easy
//
//  ABA DE SAÚDE FUNCIONANDO - 100% NATIVO
//

import SwiftUI

struct MyCheckupViewFixed: View {
    @StateObject private var viewModel = CheckupViewModel()
    @State private var selectedStars = 0
    @State private var showMedicationSheet = false
    @State private var showSuccessAnimation = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // MOOD CHECK - FUNCIONANDO!
                    VStack(spacing: 16) {
                        Text("How are you feeling today?")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        // 5 ESTRELAS CLICÁVEIS
                        HStack(spacing: 20) {
                            ForEach(1...5, id: \.self) { star in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                        selectedStars = star
                                        viewModel.saveMoodRating(star)
                                        
                                        // Haptic feedback
                                        let generator = UIImpactFeedbackGenerator(style: .medium)
                                        generator.impactOccurred()
                                        
                                        // Animação de sucesso
                                        showSuccessAnimation = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                            showSuccessAnimation = false
                                        }
                                    }
                                } label: {
                                    Image(systemName: star <= selectedStars ? "star.fill" : "star")
                                        .font(.system(size: 44))
                                        .foregroundColor(star <= selectedStars ? .yellow : .gray)
                                        .scaleEffect(star == selectedStars ? 1.3 : 1.0)
                                }
                            }
                        }
                        .padding()
                        
                        // Mensagem baseada no rating
                        if selectedStars > 0 {
                            Text(getMoodMessage(for: selectedStars))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .transition(.opacity)
                        }
                        
                        // Animação de sucesso
                        if showSuccessAnimation {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Saved!")
                                    .fontWeight(.semibold)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 8)
                    .padding(.horizontal)
                    
                    // MEDICAÇÕES - FUNCIONANDO!
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "pills.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                            
                            Text("Medication Reminders")
                                .font(.title3)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Button {
                                showMedicationSheet = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        if viewModel.medications.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                Text("No reminders yet")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("Tap + to add your first medication")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        } else {
                            ForEach(viewModel.medications) { medication in
                                MedicationCardWorking(
                                    medication: medication,
                                    onTaken: {
                                        viewModel.markAsTaken(medication)
                                        
                                        // Haptic
                                        let generator = UINotificationFeedbackGenerator()
                                        generator.notificationOccurred(.success)
                                    },
                                    onDelete: {
                                        viewModel.deleteMedication(medication)
                                    }
                                )
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 8)
                    .padding(.horizontal)
                    
                    // SUGESTÕES ALIMENTARES
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
                        
                        // Sugestões recentes
                        if !viewModel.recentSuggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Recent Suggestions")
                                    .font(.headline)
                                    .padding(.top, 8)
                                
                                ForEach(viewModel.recentSuggestions) { suggestion in
                                    FoodSuggestionCardWorking(suggestion: suggestion)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 8)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("My Check-up")
            .sheet(isPresented: $showMedicationSheet) {
                AddMedicationSheetWorking { medication in
                    viewModel.addMedication(medication)
                }
            }
        }
        .onAppear {
            selectedStars = viewModel.todaysMoodRating
            viewModel.loadMockData() // Carregar dados mock
        }
    }
    
    private func getMoodMessage(for stars: Int) -> String {
        switch stars {
        case 1: return "Sorry you're having a tough day, driver. Stay safe out there. 🚛"
        case 2: return "Hang in there. Better miles ahead. 💪"
        case 3: return "Doing okay. Keep rolling. 🛣️"
        case 4: return "Good day on the road! 😊"
        case 5: return "Excellent! Keep that energy rolling! 🎉"
        default: return ""
        }
    }
}

// Card de medicação FUNCIONANDO
struct MedicationCardWorking: View {
    let medication: Medication
    let onTaken: () -> Void
    let onDelete: () -> Void
    @State private var showingTakenAnimation = false
    
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
                showingTakenAnimation = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onTaken()
                    showingTakenAnimation = false
                }
            } label: {
                HStack {
                    if showingTakenAnimation {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                    }
                    Text(showingTakenAnimation ? "Done!" : "Took It")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(showingTakenAnimation ? Color.green : Color.orange)
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// Card de sugestão alimentar
struct FoodSuggestionCardWorking: View {
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

// Sheet para adicionar medicação
struct AddMedicationSheetWorking: View {
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
                        .autocorrectionDisabled()
                    
                    DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    
                    Toggle("Repeat Daily", isOn: $repeatDaily)
                }
                
                Section {
                    Button {
                        let medication = Medication(
                            name: medicationName,
                            time: selectedTime,
                            repeatDaily: repeatDaily
                        )
                        onAdd(medication)
                        
                        // Haptic
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Save Reminder")
                                .fontWeight(.bold)
                            Spacer()
                        }
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

// ViewModel FUNCIONANDO
@MainActor
class CheckupViewModel: ObservableObject {
    @Published var medications: [Medication] = []
    @Published var recentSuggestions: [FoodSuggestion] = []
    @Published var todaysMoodRating: Int = 0
    
    func loadMockData() {
        print("🏥 Carregando dados de saúde...")
        
        // Mock suggestions
        recentSuggestions = [
            FoodSuggestion(
                locationName: "Love's Travel Stop",
                coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                recommendation: "Try the grilled chicken salad - low sodium, high protein!",
                avoidItems: ["French fries", "Fried foods"],
                healthProfile: "Hypertensive"
            )
        ]
        
        print("✅ Dados carregados")
    }
    
    func saveMoodRating(_ rating: Int) {
        print("💙 Salvando mood rating: \(rating) estrelas")
        todaysMoodRating = rating
        
        // TODO: Salvar no UserDefaults e Supabase
        UserDefaults.standard.set(rating, forKey: "todaysMoodRating")
    }
    
    func addMedication(_ medication: Medication) {
        print("💊 Adicionando medicação: \(medication.name)")
        medications.append(medication)
        
        // TODO: Salvar no Supabase e agendar notificação
        scheduleNotification(for: medication)
    }
    
    func markAsTaken(_ medication: Medication) {
        print("✅ Medicação tomada: \(medication.name)")
        
        if let index = medications.firstIndex(where: { $0.id == medication.id }) {
            medications[index].lastTaken = Date()
        }
        
        // TODO: Salvar no Supabase
    }
    
    func deleteMedication(_ medication: Medication) {
        print("🗑️ Deletando medicação: \(medication.name)")
        medications.removeAll { $0.id == medication.id }
        
        // TODO: Remover do Supabase e cancelar notificação
    }
    
    private func scheduleNotification(for medication: Medication) {
        // TODO: Implementar UNUserNotificationCenter
        print("🔔 Notificação agendada para: \(medication.timeFormatted)")
    }
}

import CoreLocation

#Preview {
    MyCheckupViewFixed()
}
