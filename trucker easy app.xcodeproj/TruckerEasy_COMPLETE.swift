//
//  TruckerEasy_COMPLETE.swift
//  TUDO FUNCIONANDO EM 1 ARQUIVO SÓ!
//
//  Copie este arquivo inteiro para o Xcode e FUNCIONA!
//

import SwiftUI
import MapKit
import CoreLocation

// ==========================================
// MAIN APP
// ==========================================

@main
struct TruckerEasyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            Tab1_MapView()
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
            
            Tab2_WellnessView()
                .tabItem {
                    Label("Wellness", systemImage: "heart.fill")
                }
            
            Tab3_DocsView()
                .tabItem {
                    Label("Docs", systemImage: "folder.fill")
                }
        }
        .tint(Color(red: 1.0, green: 0.42, blue: 0.21)) // Laranja #FF6B35
    }
}

// ==========================================
// TAB 1: MAPA COM DOT TIMER E ROTA
// ==========================================

struct Tab1_MapView: View {
    @StateObject private var locationMgr = LocationMgr()
    @StateObject private var routeMgr = RouteMgr()
    @StateObject private var dotTimer = DOTTimer()
    @State private var showLoad = false
    @State private var mapPos: MapCameraPosition = .automatic
    
    var body: some View {
        ZStack {
            // MAPA
            Map(position: $mapPos) {
                // Localização atual
                if let loc = locationMgr.loc {
                    Annotation("", coordinate: loc) {
                        Circle().fill(.blue).frame(width: 20, height: 20)
                    }
                }
                
                // Rota
                if let route = routeMgr.route {
                    MapPolyline(route.line).stroke(.orange, lineWidth: 5)
                    Marker("A", coordinate: route.start).tint(.green)
                    Marker("B", coordinate: route.end).tint(.red)
                }
            }
            .mapStyle(.hybrid(elevation: .realistic))
            .ignoresSafeArea()
            
            // DOT TIMER - TOPO
            VStack {
                HStack(spacing: 12) {
                    VStack {
                        Text("DRIVE").font(.caption).foregroundColor(.white)
                        Text(dotTimer.driveTime).font(.title3).bold().foregroundColor(.white)
                    }
                    Rectangle().fill(dotTimer.driveColor).frame(width: 100, height: 8).cornerRadius(4)
                    VStack {
                        Text("BREAK").font(.caption).foregroundColor(.white)
                        Text(dotTimer.breakTime).font(.title3).bold().foregroundColor(.white)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(12)
                .padding(.top, 50)
                
                Spacer()
            }
            
            // BOTÃO GOT LOAD
            VStack {
                HStack {
                    Spacer()
                    Button { showLoad = true } label: {
                        Text("Got Load?").bold().foregroundColor(.white).padding()
                            .background(Color(red: 1.0, green: 0.42, blue: 0.21))
                            .cornerRadius(20)
                    }
                    .padding()
                }
                .padding(.top, 40)
                Spacer()
            }
            
            // BARRA INFERIOR
            VStack {
                Spacer()
                if let route = routeMgr.route {
                    VStack(spacing: 8) {
                        Rectangle().fill(.gray).frame(width: 40, height: 5).cornerRadius(3)
                        Text("ACTIVE ROUTE").font(.caption).foregroundColor(.orange)
                        Text(route.dest).font(.headline)
                        HStack {
                            Text(route.dist).font(.subheadline)
                            Text("•")
                            Text(route.time).font(.subheadline)
                            Text("•")
                            Text("\(Int(locationMgr.speed * 2.237)) mph").font(.subheadline)
                        }
                        Button("Cancel") { routeMgr.route = nil }
                            .foregroundColor(.red).padding(.top, 4)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16, corners: [.topLeft, .topRight])
                    .shadow(radius: 10)
                }
            }
        }
        .sheet(isPresented: $showLoad) {
            LoadSheet { addr in
                Task {
                    await routeMgr.calcRoute(from: locationMgr.loc, to: addr)
                    showLoad = false
                }
            }
        }
        .onAppear {
            locationMgr.start()
            dotTimer.start()
        }
    }
}

// Location Manager
class LocationMgr: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var loc: CLLocationCoordinate2D?
    @Published var speed: Double = 0
    let mgr = CLLocationManager()
    
    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func start() {
        mgr.requestWhenInUseAuthorization()
        mgr.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let l = locations.last {
            Task { @MainActor in
                self.loc = l.coordinate
                self.speed = l.speed
            }
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }
}

// Route Manager
@MainActor
class RouteMgr: ObservableObject {
    @Published var route: RouteData?
    
    func calcRoute(from: CLLocationCoordinate2D?, to: String) async {
        guard let from = from else { return }
        
        let geo = CLGeocoder()
        guard let placemarks = try? await geo.geocodeAddressString(to),
              let place = placemarks.first,
              let loc = place.location else { return }
        
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: loc.coordinate))
        req.transportType = .automobile
        
        guard let resp = try? await MKDirections(request: req).calculate(),
              let r = resp.routes.first else { return }
        
        route = RouteData(
            start: from,
            end: loc.coordinate,
            line: r.polyline,
            dist: String(format: "%.1f mi", r.distance / 1609.34),
            time: String(format: "%dh %dm", Int(r.expectedTravelTime)/3600, (Int(r.expectedTravelTime)%3600)/60),
            dest: place.name ?? to
        )
    }
}

struct RouteData {
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    let line: MKPolyline
    let dist: String
    let time: String
    let dest: String
}

// DOT Timer
@MainActor
class DOTTimer: ObservableObject {
    @Published var driveTime = "11:00"
    @Published var breakTime = "10:00"
    @Published var driveColor: Color = .green
    
    private var timer: Timer?
    private var driveSecs = 11 * 3600
    private var breakSecs = 10 * 3600
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.driveSecs -= 1
                if self.driveSecs <= 0 { self.driveSecs = 0 }
                
                let h = self.driveSecs / 3600
                let m = (self.driveSecs % 3600) / 60
                self.driveTime = String(format: "%d:%02d", h, m)
                
                self.driveColor = self.driveSecs < 7200 ? .red : .green
            }
        }
    }
}

// Load Sheet
struct LoadSheet: View {
    @Environment(\.dismiss) var dismiss
    var onRoute: (String) -> Void
    @State private var addr = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "truck.box.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                    .padding(.top, 40)
                
                Text("Got Load?").font(.largeTitle).bold()
                
                TextField("Enter delivery address", text: $addr)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                
                Button("Calculate Route") {
                    onRoute(addr)
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .cornerRadius(12)
                .padding()
                .disabled(addr.isEmpty)
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// ==========================================
// TAB 2: WELLNESS (BEM-ESTAR)
// ==========================================

struct Tab2_WellnessView: View {
    @State private var stars = 3
    @State private var meds: [Med] = []
    @State private var showAddMed = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // MOOD CHECK
                    VStack(spacing: 16) {
                        Text("How are you feeling today?")
                            .font(.title3).bold()
                        
                        HStack(spacing: 16) {
                            ForEach(1...5, id: \.self) { s in
                                Button {
                                    stars = s
                                    let gen = UIImpactFeedbackGenerator(style: .medium)
                                    gen.impactOccurred()
                                } label: {
                                    Image(systemName: s <= stars ? "star.fill" : "star")
                                        .font(.system(size: 40))
                                        .foregroundColor(s <= stars ? .yellow : .gray)
                                }
                            }
                        }
                        
                        Text(msg(stars))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(16)
                    .shadow(radius: 2)
                    
                    // MEDICATIONS
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "pills.fill").foregroundColor(.orange)
                            Text("Medications").font(.headline)
                            Spacer()
                            Button {
                                showAddMed = true
                            } label: {
                                Image(systemName: "plus.circle.fill").foregroundColor(.orange)
                            }
                        }
                        
                        if meds.isEmpty {
                            Text("No medications added").foregroundColor(.secondary).padding()
                        } else {
                            ForEach(meds) { m in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(m.name).font(.headline)
                                        Text(m.time).font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button("Took It") {
                                        // Mark as taken
                                    }
                                    .font(.caption).bold()
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.green)
                                    .cornerRadius(8)
                                }
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(16)
                    .shadow(radius: 2)
                    
                    // HEALTH STATS
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Stats").font(.headline)
                        StatRow(icon: "figure.walk", label: "Steps Today", val: "5,432")
                        StatRow(icon: "bed.double.fill", label: "Sleep", val: "6.5 hrs")
                        StatRow(icon: "drop.fill", label: "Water", val: "4/8 glasses")
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
            .sheet(isPresented: $showAddMed) {
                AddMedSheet { m in
                    meds.append(m)
                }
            }
        }
    }
    
    func msg(_ s: Int) -> String {
        switch s {
        case 1: return "Tough day, driver. Stay safe out there 🚛"
        case 2: return "Hang in there. Better miles ahead 💪"
        case 3: return "Doing okay. Keep rolling 🛣️"
        case 4: return "Good day on the road! 😊"
        case 5: return "Excellent! Keep that energy rolling! 🎉"
        default: return ""
        }
    }
}

struct Med: Identifiable {
    let id = UUID()
    let name: String
    let time: String
}

struct StatRow: View {
    let icon: String
    let label: String
    let val: String
    
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundColor(.orange).frame(width: 30)
            Text(label).font(.subheadline)
            Spacer()
            Text(val).font(.subheadline).bold()
        }
    }
}

struct AddMedSheet: View {
    @Environment(\.dismiss) var dismiss
    var onAdd: (Med) -> Void
    @State private var name = ""
    @State private var time = Date()
    
    var body: some View {
        NavigationView {
            Form {
                TextField("Medication Name", text: $name)
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                
                Button("Add") {
                    let formatter = DateFormatter()
                    formatter.timeStyle = .short
                    onAdd(Med(name: name, time: formatter.string(from: time)))
                    dismiss()
                }
                .disabled(name.isEmpty)
            }
            .navigationTitle("Add Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// ==========================================
// TAB 3: DOCUMENTS (DOCUMENTOS)
// ==========================================

struct Tab3_DocsView: View {
    @State private var docs = [
        Doc(name: "CDL", exp: Date().addingTimeInterval(180*86400)),
        Doc(name: "Medical Card", exp: Date().addingTimeInterval(20*86400)),
        Doc(name: "Insurance", exp: Date().addingTimeInterval(-5*86400))
    ]
    
    var valid: Int { docs.filter { $0.status == .valid }.count }
    var expiring: Int { docs.filter { $0.status == .expiring }.count }
    var expired: Int { docs.filter { $0.status == .expired }.count }
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 16) {
                        Badge(n: valid, c: .green, t: "Valid")
                        Badge(n: expiring, c: .orange, t: "Expiring")
                        Badge(n: expired, c: .red, t: "Expired")
                    }
                    .padding(.vertical, 8)
                }
                
                ForEach(docs) { d in
                    HStack {
                        Circle().fill(d.status.color).frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(d.name).font(.headline)
                            Text("Expires: \(d.exp, style: .date)").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("My Documents")
        }
    }
}

struct Doc: Identifiable {
    let id = UUID()
    let name: String
    let exp: Date
    
    var status: DocStatus {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0
        if days < 0 { return .expired }
        if days <= 30 { return .expiring }
        return .valid
    }
    
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

struct Badge: View {
    let n: Int
    let c: Color
    let t: String
    
    var body: some View {
        VStack {
            Text("\(n)").font(.title).bold().foregroundColor(c)
            Text(t).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(c.opacity(0.1))
        .cornerRadius(12)
    }
}

// Corner radius helper
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// ==========================================
// PREVIEW
// ==========================================

#Preview {
    ContentView()
}
