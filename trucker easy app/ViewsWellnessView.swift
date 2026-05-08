//
//  WellnessView.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 3/1/26.
//

import SwiftUI
import SwiftData

enum WellnessCategory: String, Codable, CaseIterable {
    case rest = "Rest & Sleep"
    case exercise = "Exercise"
    case nutrition = "Nutrition"
    case mental = "Mental Health"
    case safety = "Safety"
}

@Model
final class WellnessLog {
    var id: UUID
    var date: Date
    var categoryRaw: String
    var hoursSlept: Double?
    var exerciseMinutes: Int?
    var waterIntake: Int? // glasses
    var mealQuality: Int? // 1-5 rating
    var stressLevel: Int? // 1-5 rating
    var notes: String
    
    var category: WellnessCategory {
        get { WellnessCategory(rawValue: categoryRaw) ?? .rest }
        set { categoryRaw = newValue.rawValue }
    }
    
    init(category: WellnessCategory, date: Date = Date(), notes: String = "") {
        self.id = UUID()
        self.date = date
        self.categoryRaw = category.rawValue
        self.notes = notes
    }
}

struct WellnessView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WellnessLog.date, order: .reverse) private var logs: [WellnessLog]
    
    @State private var showingAddLog = false
    @State private var selectedCategory: WellnessCategory?
    
    var filteredLogs: [WellnessLog] {
        if let category = selectedCategory {
            return logs.filter { $0.category == category }
        }
        return logs
    }
    
    var todayLogs: [WellnessLog] {
        let calendar = Calendar.current
        return logs.filter { calendar.isDateInToday($0.date) }
    }
    
    var averageSleepThisWeek: Double {
        let calendar = Calendar.current
        let weekLogs = logs.filter {
            calendar.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear) &&
            $0.hoursSlept != nil
        }
        
        guard !weekLogs.isEmpty else { return 0 }
        let total = weekLogs.compactMap { $0.hoursSlept }.reduce(0, +)
        return total / Double(weekLogs.count)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Daily Summary
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Today's Wellness"))
                            .font(.headline)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            WellnessCard(
                                title: String(localized: "Sleep"),
                                value: todayLogs.first(where: { $0.hoursSlept != nil })?.hoursSlept.map { String(format: "%.1f hrs", $0) } ?? "--",
                                icon: "bed.double.fill",
                                color: .blue
                            )
                            
                            WellnessCard(
                                title: String(localized: "Exercise"),
                                value: todayLogs.first(where: { $0.exerciseMinutes != nil })?.exerciseMinutes.map { "\($0) min" } ?? "--",
                                icon: "figure.walk",
                                color: .green
                            )
                            
                            WellnessCard(
                                title: String(localized: "Water"),
                                value: todayLogs.first(where: { $0.waterIntake != nil })?.waterIntake.map { "\($0) glasses" } ?? "--",
                                icon: "drop.fill",
                                color: .cyan
                            )
                            
                            WellnessCard(
                                title: String(localized: "Stress"),
                                value: todayLogs.first(where: { $0.stressLevel != nil })?.stressLevel.map { "\($0)/5" } ?? "--",
                                icon: "brain.head.profile",
                                color: .orange
                            )
                        }
                        .padding(.horizontal)
                    }
                    
                    // Weekly Average
                    if averageSleepThisWeek > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "Weekly Average Sleep"))
                                .font(.headline)
                                .padding(.horizontal)
                            
                            HStack {
                                Image(systemName: "moon.stars.fill")
                                    .foregroundColor(.blue)
                                
                                Text(String(format: "%.1f hours", averageSleepThisWeek))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                Spacer()
                                
                                Text(averageSleepThisWeek >= 7 ? "✓ Good" : "⚠️ Need more")
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(averageSleepThisWeek >= 7 ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                                    .cornerRadius(12)
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .shadow(radius: 2)
                            .padding(.horizontal)
                        }
                    }
                    
                    // Tips Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Wellness Tips"))
                            .font(.headline)
                            .padding(.horizontal)
                        
                        WellnessTipCard(
                            icon: "bed.double.fill",
                            title: String(localized: "Rest Regularly"),
                            description: String(localized: "Aim for 7-8 hours of sleep per night"),
                            color: .blue
                        )
                        
                        WellnessTipCard(
                            icon: "figure.walk",
                            title: String(localized: "Stay Active"),
                            description: String(localized: "Take breaks to stretch and walk every 2 hours"),
                            color: .green
                        )
                        
                        WellnessTipCard(
                            icon: "fork.knife",
                            title: String(localized: "Eat Healthy"),
                            description: String(localized: "Choose nutritious meals and stay hydrated"),
                            color: .orange
                        )
                    }
                    
                    // Category Filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            FilterChip(
                                title: String(localized: "All"),
                                isSelected: selectedCategory == nil,
                                action: { selectedCategory = nil }
                            )
                            
                            ForEach(WellnessCategory.allCases, id: \.self) { category in
                                FilterChip(
                                    title: String(localized: LocalizedStringResource(stringLiteral: category.rawValue)),
                                    isSelected: selectedCategory == category,
                                    action: { selectedCategory = category }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Logs List
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Activity Log"))
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(filteredLogs) { log in
                            WellnessLogRow(log: log)
                        }
                        
                        if filteredLogs.isEmpty {
                            Text(String(localized: "No wellness logs yet. Start tracking your health!"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "Wellness"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddLog = true }) {
                        Label("Add Log", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddLog) {
                AddWellnessLogView()
            }
        }
    }
}

struct WellnessCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct WellnessTipCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 50, height: 50)
                .background(color.opacity(0.1))
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

struct WellnessLogRow: View {
    let log: WellnessLog
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(log.category.rawValue)
                    .font(.headline)
                
                Spacer()
                
                Text(log.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let hours = log.hoursSlept {
                Label(String(format: "%.1f hours sleep", hours), systemImage: "bed.double.fill")
                    .font(.caption)
            }
            
            if let minutes = log.exerciseMinutes {
                Label("\(minutes) min exercise", systemImage: "figure.walk")
                    .font(.caption)
            }
            
            if let water = log.waterIntake {
                Label("\(water) glasses water", systemImage: "drop.fill")
                    .font(.caption)
            }
            
            if let stress = log.stressLevel {
                Label("Stress level: \(stress)/5", systemImage: "brain.head.profile")
                    .font(.caption)
            }
            
            if !log.notes.isEmpty {
                Text(log.notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

struct AddWellnessLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var category = WellnessCategory.rest
    @State private var hoursSlept = 7.0
    @State private var exerciseMinutes = 30
    @State private var waterIntake = 8
    @State private var mealQuality = 3
    @State private var stressLevel = 3
    @State private var notes = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Category")) {
                    Picker(String(localized: "Type"), selection: $category) {
                        ForEach(WellnessCategory.allCases, id: \.self) { cat in
                            Text(LocalizedStringResource(stringLiteral: cat.rawValue)).tag(cat)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section(String(localized: "Metrics")) {
                    VStack(alignment: .leading) {
                        Text(String(localized: "Hours Slept: \(String(format: "%.1f", hoursSlept))"))
                        Slider(value: $hoursSlept, in: 0...12, step: 0.5)
                    }
                    
                    Stepper(String(localized: "Exercise: \(exerciseMinutes) min"), value: $exerciseMinutes, in: 0...180, step: 5)
                    
                    Stepper(String(localized: "Water: \(waterIntake) glasses"), value: $waterIntake, in: 0...20)
                    
                    VStack(alignment: .leading) {
                        Text(String(localized: "Meal Quality: \(mealQuality)/5"))
                        Slider(value: Binding(
                            get: { Double(mealQuality) },
                            set: { mealQuality = Int($0) }
                        ), in: 1...5, step: 1)
                    }
                    
                    VStack(alignment: .leading) {
                        Text(String(localized: "Stress Level: \(stressLevel)/5"))
                        Slider(value: Binding(
                            get: { Double(stressLevel) },
                            set: { stressLevel = Int($0) }
                        ), in: 1...5, step: 1)
                    }
                }
                
                Section(String(localized: "Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle(String(localized: "Log Wellness"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        saveLog()
                    }
                }
            }
        }
    }
    
    private func saveLog() {
        let log = WellnessLog(category: category, notes: notes)
        log.hoursSlept = hoursSlept
        log.exerciseMinutes = exerciseMinutes
        log.waterIntake = waterIntake
        log.mealQuality = mealQuality
        log.stressLevel = stressLevel
        
        modelContext.insert(log)
        dismiss()
    }
}

#Preview {
    WellnessView()
        .modelContainer(for: WellnessLog.self, inMemory: true)
}
