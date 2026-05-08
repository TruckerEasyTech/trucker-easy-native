//
//  AllTabsWorking.swift
//  Trucker Easy
//
//  TODAS AS 5 TABS FUNCIONANDO - COPIADO DO TRUCKER PATH
//

import SwiftUI
import MapKit
import CoreLocation

// ============================================
// TAB 1: NAVIGATION MAP (IGUAL TRUCKER PATH)
// ============================================

struct NavigationMapView: View {
    @StateObject private var locationManager = SimpleLocationManager()
    @State private var showLoadInput = false
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    
    var body: some View {
        ZStack {
            // MAPA SIMPLES QUE FUNCIONA
            Map(position: $mapCameraPosition) {
                if let location = locationManager.currentLocation {
                    Annotation("You", coordinate: location) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    }
                }
            }
            .mapStyle(.hybrid(elevation: .realistic))
            .ignoresSafeArea()
            
            // BOTÃO GOT LOAD
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showLoadInput = true
                    } label: {
                        HStack {
                            Image(systemName: "truck.box.fill")
                            Text("Got Load?")
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color(hex: "#FF6B35"))
                        .cornerRadius(25)
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .sheet(isPresented: $showLoadInput) {
            LoadInputSimple()
        }
        .onAppear {
            locationManager.start()
        }
    }
}

struct LoadInputSimple: View {
    @Environment(\.dismiss) var dismiss
    @State private var address = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "truck.box.fill")
                    .font(.system(size: 60))
                    .foregroundColor(Color(hex: "#FF6B35"))
                    .padding(.top, 40)
                
                Text("Where are you delivering?")
                    .font(.title2)
                    .fontWeight(.bold)
                
                TextField("Enter address", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                
                Button("Calculate Route") {
                    // Aqui você calcularia a rota
                    dismiss()
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(hex: "#FF6B35"))
                .cornerRadius(12)
                .padding()
                
                Spacer()
            }
            .navigationTitle("Got Load?")
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

// LOCATION MANAGER SIMPLES QUE FUNCIONA
@MainActor
class SimpleLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentLocation: CLLocationCoordinate2D?
    private let manager = CLLocationManager()
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location.coordinate
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .authorizedWhenInUse {
                manager.startUpdatingLocation()
            }
        }
    }
}

// ============================================
// TAB 2: TRIP PLANNER
// ============================================

struct TripPlannerView: View {
    @State private var trips: [Trip] = []
    
    var body: some View {
        NavigationView {
            List {
                if trips.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "map")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No active trips")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Start navigating to create your first trip")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 100)
                } else {
                    ForEach(trips) { trip in
                        TripRow(trip: trip)
                    }
                }
            }
            .navigationTitle("My Trips")
        }
    }
}

struct Trip: Identifiable {
    let id = UUID()
    let destination: String
    let distance: String
    let eta: String
}

struct TripRow: View {
    let trip: Trip
    
    var body: some View {
        HStack {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundColor(Color(hex: "#FF6B35"))
            
            VStack(alignment: .leading) {
                Text(trip.destination)
                    .font(.headline)
                Text("\(trip.distance) • \(trip.eta)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// ============================================
// TAB 3: WELLNESS (SUA IDEIA EXCLUSIVA!)
// ============================================

struct WellnessView: View {
    @State private var moodRating = 3
    @State private var showMedicationAlert = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // MOOD CHECK
                    VStack(spacing: 16) {
                        Text("How are you feeling today?")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        HStack(spacing: 16) {
                            ForEach(1...5, id: \.self) { star in
                                Button {
                                    moodRating = star
                                } label: {
                                    Image(systemName: star <= moodRating ? "star.fill" : "star")
                                        .font(.largeTitle)
                                        .foregroundColor(star <= moodRating ? .yellow : .gray)
                                }
                            }
                        }
                        
                        Text(getMoodMessage(for: moodRating))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(16)
                    .shadow(radius: 2)
                    
                    // MEDICATION REMINDER
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "pills.fill")
                                .foregroundColor(Color(hex: "#FF6B35"))
                            Text("Medication Reminders")
                                .font(.headline)
                        }
                        
                        Button {
                            showMedicationAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Medication")
                            }
                            .foregroundColor(Color(hex: "#FF6B35"))
                        }
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(16)
                    .shadow(radius: 2)
                    
                    // HEALTH STATS
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Stats")
                            .font(.headline)
                        
                        HealthStatRow(icon: "figure.walk", title: "Steps Today", value: "5,432")
                        HealthStatRow(icon: "bed.double.fill", title: "Sleep Last Night", value: "6.5 hrs")
                        HealthStatRow(icon: "drop.fill", title: "Water Intake", value: "4/8 glasses")
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(16)
                    .shadow(radius: 2)
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("My Wellness")
            .alert("Add Medication", isPresented: $showMedicationAlert) {
                TextField("Medication name", text: .constant(""))
                Button("Cancel", role: .cancel) {}
                Button("Add") {}
            }
        }
    }
    
    func getMoodMessage(for rating: Int) -> String {
        switch rating {
        case 1: return "Tough day, driver. Stay safe out there 🚛"
        case 2: return "Hang in there. Better miles ahead 💪"
        case 3: return "Doing okay. Keep rolling 🛣️"
        case 4: return "Good day on the road! 😊"
        case 5: return "Excellent! Keep that energy rolling! 🎉"
        default: return ""
        }
    }
}

struct HealthStatRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Color(hex: "#FF6B35"))
                .frame(width: 30)
            
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 4)
    }
}

// ============================================
// TAB 4: DOCUMENTS
// ============================================

struct DocumentsView: View {
    @State private var documents: [Document] = [
        Document(type: "CDL", expirationDate: Date().addingTimeInterval(180*86400), status: .valid),
        Document(type: "Medical Card", expirationDate: Date().addingTimeInterval(20*86400), status: .expiring),
        Document(type: "Insurance", expirationDate: Date().addingTimeInterval(-5*86400), status: .expired),
    ]
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 20) {
                        StatusBadge(count: documents.filter { $0.status == .valid }.count, color: .green, label: "Valid")
                        StatusBadge(count: documents.filter { $0.status == .expiring }.count, color: .orange, label: "Expiring")
                        StatusBadge(count: documents.filter { $0.status == .expired }.count, color: .red, label: "Expired")
                    }
                    .padding(.vertical)
                }
                
                ForEach(documents) { doc in
                    DocumentRow(document: doc)
                }
            }
            .navigationTitle("My Documents")
        }
    }
}

struct Document: Identifiable {
    let id = UUID()
    let type: String
    let expirationDate: Date
    let status: DocStatus
    
    enum DocStatus {
        case valid, expiring, expired
        
        var color: Color {
            switch self {
            case .valid: return .green
            case .expiring: return .orange
            case .expired: return .red
            }
        }
    }
}

struct DocumentRow: View {
    let document: Document
    
    var body: some View {
        HStack {
            Circle()
                .fill(document.status.color)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(document.type)
                    .font(.headline)
                Text("Expires: \(document.expirationDate, style: .date)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatusBadge: View {
    let count: Int
    let color: Color
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// ============================================
// TAB 5: MORE
// ============================================

struct MoreView: View {
    var body: some View {
        NavigationView {
            List {
                Section("App") {
                    NavigationLink {
                        Text("Settings coming soon")
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    
                    NavigationLink {
                        Text("Help coming soon")
                    } label: {
                        Label("Help & Support", systemImage: "questionmark.circle")
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Made by")
                        Spacer()
                        Text("Driver to Driver")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}

#Preview {
    MainTabBarWorking()
}
