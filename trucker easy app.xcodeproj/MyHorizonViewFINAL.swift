//
//  MyHorizonViewFINAL.swift
//  Trucker Easy
//
//  LAYOUT PROFISSIONAL IGUAL LOVABLE + TRUCKER PATH
//  COM DOT TIMER, BARRA LATERAL, TUDO FUNCIONANDO!
//

import SwiftUI
import MapKit
import CoreLocation

struct MyHorizonViewFINAL: View {
    @StateObject private var locationManager = LocationManagerFINAL()
    @StateObject private var routeManager = RouteManagerFINAL()
    @StateObject private var dotTimer = DOTTimerManager()
    
    @State private var showSideMenu = false
    @State private var showLoadSheet = false
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var selectedMapStyle: MapStyle = .hybrid(elevation: .realistic)
    
    var body: some View {
        ZStack {
            // MAPA 3D GLOBO FULL SCREEN
            MapViewFINAL(
                locationManager: locationManager,
                routeManager: routeManager,
                mapCameraPosition: $mapCameraPosition,
                selectedMapStyle: $selectedMapStyle
            )
            .ignoresSafeArea()
            
            // DOT TIMER - TOPO CENTRAL
            VStack {
                DOTTimerBar(dotTimer: dotTimer)
                    .padding(.top, 50)
                
                Spacer()
            }
            
            // BOTÃO MENU LATERAL - TOPO ESQUERDO
            VStack {
                HStack {
                    Button {
                        withAnimation(.spring()) {
                            showSideMenu.toggle()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.truckerDark.opacity(0.8))
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: "line.3.horizontal")
                                .font(.title3)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.leading, 20)
                    .padding(.top, 50)
                    
                    Spacer()
                }
                Spacer()
            }
            
            // BOTÃO "GOT LOAD?" - TOPO DIREITO
            VStack {
                HStack {
                    Spacer()
                    
                    Button {
                        showLoadSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "truck.box.fill")
                                .font(.headline)
                            Text("Got Load?")
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color.truckerPrimary, Color.truckerPrimary.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(25)
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 50)
                }
                Spacer()
            }
            
            // BARRA INFERIOR COM INFO DA ROTA
            VStack {
                Spacer()
                RouteInfoBarFINAL(
                    route: routeManager.activeRoute,
                    isCalculating: routeManager.isCalculating,
                    currentSpeed: locationManager.speed,
                    onCancelRoute: {
                        routeManager.clearRoute()
                    }
                )
            }
            
            // MENU LATERAL (SLIDE FROM LEFT)
            if showSideMenu {
                SideMenuView(
                    isShowing: $showSideMenu,
                    locationManager: locationManager,
                    dotTimer: dotTimer
                )
                .transition(.move(edge: .leading))
            }
        }
        .sheet(isPresented: $showLoadSheet) {
            LoadAddressSheetFINAL { address in
                Task {
                    await routeManager.calculateRoute(
                        from: locationManager.currentLocation,
                        to: address
                    )
                    showLoadSheet = false
                }
            }
        }
        .onAppear {
            locationManager.requestPermission()
            
            // Centralizar no usuário
            if let location = locationManager.currentLocation {
                mapCameraPosition = .camera(
                    MapCamera(
                        centerCoordinate: location,
                        distance: 5000,
                        heading: 0,
                        pitch: 60
                    )
                )
            }
        }
    }
}

// MAPA 3D FINAL
struct MapViewFINAL: View {
    @ObservedObject var locationManager: LocationManagerFINAL
    @ObservedObject var routeManager: RouteManagerFINAL
    @Binding var mapCameraPosition: MapCameraPosition
    @Binding var selectedMapStyle: MapStyle
    
    var body: some View {
        Map(position: $mapCameraPosition, interactionModes: .all) {
            // CURRENT LOCATION - PONTO AZUL PULSANTE
            if let location = locationManager.currentLocation {
                Annotation("You", coordinate: location) {
                    ZStack {
                        // Círculo pulsante externo
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 70, height: 70)
                            .scaleEffect(locationManager.isPulsing ? 1.0 : 0.7)
                            .animation(
                                .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                                value: locationManager.isPulsing
                            )
                        
                        // Círculo azul sólido
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                            )
                        
                        // Seta de direção
                        if locationManager.heading > 0 {
                            Image(systemName: "location.north.fill")
                                .foregroundColor(.white)
                                .rotationEffect(.degrees(locationManager.heading))
                        }
                    }
                }
            }
            
            // ROTA ATIVA
            if let route = routeManager.activeRoute {
                // Sombra da rota
                MapPolyline(route.polyline)
                    .stroke(.black.opacity(0.3), lineWidth: 8)
                
                // Rota principal
                MapPolyline(route.polyline)
                    .stroke(
                        .linearGradient(
                            colors: [Color.truckerPrimary, Color.truckerPrimary.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 6
                    )
                
                // Marcador ORIGEM (A)
                if let origin = locationManager.currentLocation {
                    Annotation("Start", coordinate: origin) {
                        ZStack {
                            Circle()
                                .fill(Color.statusGreen)
                                .frame(width: 40, height: 40)
                            Text("A")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        .shadow(radius: 4)
                    }
                }
                
                // Marcador DESTINO (B)
                Annotation(route.destinationName, coordinate: route.destination) {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(Color.statusRed.opacity(0.3))
                                .frame(width: 60, height: 60)
                            Circle()
                                .fill(Color.statusRed)
                                .frame(width: 40, height: 40)
                            Text("B")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        
                        Text(route.destinationName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white)
                            .cornerRadius(6)
                            .shadow(radius: 2)
                    }
                }
                
                // ALERTAS NA ROTA
                ForEach(route.alerts) { alert in
                    Annotation(alert.type, coordinate: alert.coordinate) {
                        ZStack {
                            Circle()
                                .fill(alert.color.opacity(0.9))
                                .frame(width: 36, height: 36)
                            Image(systemName: alert.icon)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .shadow(radius: 3)
                    }
                }
            }
        }
        .mapStyle(selectedMapStyle)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapPitchToggle()
            MapScaleView()
        }
    }
}

// DOT TIMER BAR (TOPO)
struct DOTTimerBar: View {
    @ObservedObject var dotTimer: DOTTimerManager
    
    var body: some View {
        HStack(spacing: 16) {
            // Drive time
            VStack(spacing: 2) {
                Text("DRIVE")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.8))
                Text(dotTimer.driveTimeRemaining)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            // Progress bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 120, height: 8)
                
                RoundedRectangle(cornerRadius: 10)
                    .fill(dotTimer.driveProgress > 0.8 ? Color.statusRed : Color.statusGreen)
                    .frame(width: 120 * dotTimer.driveProgress, height: 8)
            }
            
            // Break time
            VStack(spacing: 2) {
                Text("BREAK")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.8))
                Text(dotTimer.breakTimeRemaining)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.truckerDark.opacity(0.9))
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        )
    }
}

// BARRA INFERIOR COM INFO DA ROTA
struct RouteInfoBarFINAL: View {
    let route: TruckRouteFINAL?
    let isCalculating: Bool
    let currentSpeed: CLLocationSpeed
    let onCancelRoute: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.5))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
            
            if isCalculating {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(Color.truckerPrimary)
                    Text("Calculating route...")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                .padding()
            } else if let route = route {
                VStack(spacing: 14) {
                    // Header com destino
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ACTIVE ROUTE")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.truckerPrimary)
                            Text(route.destinationName)
                                .font(.title3)
                                .fontWeight(.bold)
                        }
                        
                        Spacer()
                        
                        Button(action: onCancelRoute) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.statusRed)
                        }
                    }
                    
                    // Stats da rota
                    HStack(spacing: 20) {
                        RouteStatView(
                            icon: "road.lanes",
                            value: route.distance,
                            label: "Distance"
                        )
                        
                        Divider()
                            .frame(height: 40)
                        
                        RouteStatView(
                            icon: "clock",
                            value: route.duration,
                            label: "ETA"
                        )
                        
                        Divider()
                            .frame(height: 40)
                        
                        RouteStatView(
                            icon: "speedometer",
                            value: String(format: "%.0f mph", currentSpeed * 2.237),
                            label: "Speed"
                        )
                    }
                    
                    // Alertas
                    if !route.alerts.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(route.alerts) { alert in
                                    HStack(spacing: 6) {
                                        Image(systemName: alert.icon)
                                            .foregroundColor(alert.color)
                                        Text(alert.type)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(alert.color.opacity(0.15))
                                    .cornerRadius(12)
                                }
                            }
                        }
                    }
                }
                .padding()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.title)
                        .foregroundColor(.truckerPrimary)
                    Text("Ready to navigate")
                        .font(.headline)
                    Text("Tap 'Got Load?' to start")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 15, y: -5)
        )
    }
}

struct RouteStatView: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.truckerPrimary)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MENU LATERAL
struct SideMenuView: View {
    @Binding var isShowing: Bool
    @ObservedObject var locationManager: LocationManagerFINAL
    @ObservedObject var dotTimer: DOTTimerManager
    
    var body: some View {
        ZStack {
            // Background escuro
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        isShowing = false
                    }
                }
            
            // Menu
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Trucker Easy")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Driver to Driver")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.truckerPrimary)
                    
                    ScrollView {
                        VStack(spacing: 0) {
                            // Location status
                            MenuItemView(
                                icon: "location.fill",
                                title: "Current Location",
                                subtitle: locationManager.currentLocation != nil ?
                                    "GPS Active" : "No GPS Signal",
                                color: locationManager.currentLocation != nil ? .statusGreen : .statusRed
                            )
                            
                            Divider()
                            
                            // DOT Status
                            MenuItemView(
                                icon: "clock.fill",
                                title: "DOT Hours",
                                subtitle: "\(dotTimer.driveTimeRemaining) remaining",
                                color: .truckerSecondary
                            )
                            
                            Divider()
                            
                            // Settings
                            MenuItemView(
                                icon: "gearshape.fill",
                                title: "Settings",
                                subtitle: "App preferences",
                                color: .gray
                            )
                            
                            Divider()
                            
                            // Help
                            MenuItemView(
                                icon: "questionmark.circle.fill",
                                title: "Help & Support",
                                subtitle: "Get assistance",
                                color: .truckerAccent
                            )
                        }
                    }
                    
                    Spacer()
                    
                    // Footer
                    Text("Version 1.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                }
                .frame(width: 280)
                .background(Color(UIColor.systemBackground))
                
                Spacer()
            }
        }
    }
}

struct MenuItemView: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// SHEET PARA ADICIONAR ENDEREÇO
struct LoadAddressSheetFINAL: View {
    @Environment(\.dismiss) var dismiss
    var onAddressSelected: (String) -> Void
    
    @State private var addressText = ""
    @State private var extractedAddress = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "truck.box.badge.clock.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.truckerPrimary)
                    
                    Text("Got Load?")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Paste load info - I'll find the address!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)
                
                // Botão colar
                Button {
                    if let clipboard = UIPasteboard.general.string {
                        addressText = clipboard
                        extractAddress(from: clipboard)
                    }
                } label: {
                    HStack {
                        Image(systemName: "doc.on.clipboard.fill")
                        Text("Paste from Clipboard")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.truckerPrimary)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                
                // Text editor
                VStack(alignment: .leading, spacing: 8) {
                    Text("Or type/paste here:")
                        .font(.headline)
                    
                    TextEditor(text: $addressText)
                        .frame(height: 120)
                        .padding(8)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(8)
                        .onChange(of: addressText) { _, new in
                            extractAddress(from: new)
                        }
                }
                .padding(.horizontal)
                
                // Endereço extraído
                if !extractedAddress.isEmpty {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.statusGreen)
                            Text("Address Found!")
                                .font(.headline)
                                .foregroundColor(.statusGreen)
                        }
                        
                        Text(extractedAddress)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.statusGreen.opacity(0.1))
                            .cornerRadius(8)
                        
                        Button {
                            onAddressSelected(extractedAddress)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                Text("Calculate Route")
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.statusGreen)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
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
    
    private func extractAddress(from text: String) {
        let patterns = [
            #"(\d+\s+[A-Za-z0-9\s,\.]+(?:Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Drive|Dr|Lane|Ln)[A-Za-z\s,\.]*,\s*[A-Za-z\s]+,\s*[A-Z]{2}\s*\d{5})"#,
            #"([A-Za-z\s]+,\s*[A-Z]{2}\s*\d{5})"#,
            #"(\d+\s+[A-Za-z0-9\s\.]+,\s*[A-Za-z\s]+,\s*[A-Z]{2})"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                extractedAddress = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                return
            }
        }
        
        extractedAddress = ""
    }
}

// LOCATION MANAGER FINAL
@MainActor
class LocationManagerFINAL: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var heading: CLLocationDirection = 0
    @Published var speed: CLLocationSpeed = 0
    @Published var isPulsing = true
    
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5
    }
    
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            self.currentLocation = location.coordinate
            self.speed = location.speed
            print("📍 Location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            self.heading = newHeading.trueHeading
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
                manager.startUpdatingHeading()
            }
        }
    }
}

// ROUTE MANAGER FINAL
@MainActor
class RouteManagerFINAL: ObservableObject {
    @Published var activeRoute: TruckRouteFINAL?
    @Published var isCalculating = false
    
    func calculateRoute(from origin: CLLocationCoordinate2D?, to address: String) async {
        guard let origin = origin else { return }
        
        isCalculating = true
        print("🧭 Calculating route...")
        
        do {
            let geocoder = CLGeocoder()
            let placemarks = try await geocoder.geocodeAddressString(address)
            
            guard let destination = placemarks.first?.location?.coordinate else {
                print("❌ Address not found")
                isCalculating = false
                return
            }
            
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
            request.transportType = .automobile
            
            let directions = MKDirections(request: request)
            let response = try await directions.calculate()
            
            guard let route = response.routes.first else {
                print("❌ No route found")
                isCalculating = false
                return
            }
            
            activeRoute = TruckRouteFINAL(
                destinationName: placemarks.first?.name ?? address,
                destination: destination,
                polyline: route.polyline,
                distance: formatDistance(route.distance),
                duration: formatDuration(route.expectedTravelTime),
                alerts: generateAlerts(for: route)
            )
            
            print("✅ Route calculated!")
        } catch {
            print("❌ Error: \(error)")
        }
        
        isCalculating = false
    }
    
    func clearRoute() {
        activeRoute = nil
    }
    
    private func formatDistance(_ meters: CLLocationDistance) -> String {
        String(format: "%.1f mi", meters / 1609.34)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
    
    private func generateAlerts(for route: MKRoute) -> [RouteAlert] {
        var alerts: [RouteAlert] = []
        
        if route.steps.count > 2 {
            let midPoint = route.steps[route.steps.count / 2].polyline.coordinate
            alerts.append(RouteAlert(
                type: "Bridge Ahead",
                coordinate: midPoint,
                icon: "figure.walk.motion",
                color: .statusYellow
            ))
        }
        
        return alerts
    }
}

// DOT TIMER MANAGER
@MainActor
class DOTTimerManager: ObservableObject {
    @Published var driveTimeRemaining = "10:30"
    @Published var breakTimeRemaining = "8:00"
    @Published var driveProgress: Double = 0.3
    
    private var timer: Timer?
    
    init() {
        startTimer()
    }
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Update timers
        }
    }
}

// MODELS
struct TruckRouteFINAL: Identifiable {
    let id = UUID()
    let destinationName: String
    let destination: CLLocationCoordinate2D
    let polyline: MKPolyline
    let distance: String
    let duration: String
    let alerts: [RouteAlert]
}

struct RouteAlert: Identifiable {
    let id = UUID()
    let type: String
    let coordinate: CLLocationCoordinate2D
    let icon: String
    let color: Color
}

#Preview {
    MyHorizonViewFINAL()
}
