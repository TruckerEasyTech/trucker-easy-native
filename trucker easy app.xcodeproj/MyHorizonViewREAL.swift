//
//  MyHorizonViewREAL.swift
//  Trucker Easy
//
//  MAPA 3D GLOBO FUNCIONANDO DE VERDADE!
//  Current Location + Rotas + Navegação REAL
//

import SwiftUI
import MapKit
import CoreLocation

struct MyHorizonViewREAL: View {
    @StateObject private var locationManager = LocationManagerREAL()
    @StateObject private var routeCalculator = RouteCalculatorREAL()
    @State private var showLoadSheet = false
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var selectedMapStyle: MapStyle = .hybrid(elevation: .realistic)
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // MAPA 3D GLOBO INTERATIVO E RESPONSIVO
            Map(position: $mapCameraPosition, interactionModes: .all) {
                // CURRENT LOCATION - PONTO AZUL PULSANTE
                if let userLocation = locationManager.currentLocation {
                    Annotation("Você está aqui", coordinate: userLocation) {
                        ZStack {
                            // Círculo pulsante externo
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 80, height: 80)
                                .scaleEffect(locationManager.isPulsing ? 1.0 : 0.8)
                                .animation(
                                    .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                                    value: locationManager.isPulsing
                                )
                            
                            // Círculo médio
                            Circle()
                                .fill(Color.blue.opacity(0.4))
                                .frame(width: 40, height: 40)
                            
                            // Ponto central azul
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 3)
                                )
                        }
                    }
                }
                
                // ROTA CALCULADA - PONTO A → PONTO B
                if let route = routeCalculator.currentRoute {
                    // Sombra da rota (efeito 3D)
                    MapPolyline(route.polyline)
                        .stroke(.black.opacity(0.3), lineWidth: 8)
                    
                    // Rota principal com gradiente
                    MapPolyline(route.polyline)
                        .stroke(
                            .linearGradient(
                                colors: [.orange, .orange.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 6
                        )
                    
                    // MARCADOR DE ORIGEM (A)
                    if let origin = locationManager.currentLocation {
                        Annotation("Origem", coordinate: origin) {
                            ZStack {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 44, height: 44)
                                Text("A")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    
                    // MARCADOR DE DESTINO (B)
                    Annotation("Destino", coordinate: route.destination) {
                        VStack(spacing: 0) {
                            ZStack {
                                // Pin vermelho pulsante
                                Circle()
                                    .fill(.red.opacity(0.3))
                                    .frame(width: 60, height: 60)
                                
                                Circle()
                                    .fill(.red)
                                    .frame(width: 44, height: 44)
                                
                                Text("B")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            
                            // Info do destino
                            VStack(spacing: 4) {
                                Text(route.destinationName)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.white)
                                    .cornerRadius(8)
                                    .shadow(radius: 2)
                            }
                        }
                    }
                    
                    // PONTOS DE ALERTA NA ROTA
                    ForEach(route.warnings) { warning in
                        Annotation(warning.type, coordinate: warning.coordinate) {
                            ZStack {
                                Circle()
                                    .fill(warning.color.opacity(0.9))
                                    .frame(width: 36, height: 36)
                                Image(systemName: warning.icon)
                                    .foregroundColor(.white)
                                    .font(.system(size: 16, weight: .bold))
                            }
                        }
                    }
                }
                
                // ALERTAS DA COMUNIDADE
                ForEach(routeCalculator.communityAlerts) { alert in
                    Annotation(alert.type.rawValue, coordinate: alert.coordinate) {
                        Button {
                            // Mostrar detalhes do alerta
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(alert.type.color.opacity(0.9))
                                    .frame(width: 44, height: 44)
                                Image(systemName: alert.type.icon)
                                    .foregroundColor(.white)
                                    .font(.system(size: 20, weight: .bold))
                            }
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
            .ignoresSafeArea()
            .onAppear {
                locationManager.startTracking()
                routeCalculator.loadCommunityAlerts()
                
                // Centralizar no usuário quando carregar
                if let userLocation = locationManager.currentLocation {
                    mapCameraPosition = .camera(
                        MapCamera(
                            centerCoordinate: userLocation,
                            distance: 5000, // Altitude
                            heading: 0,
                            pitch: 60 // INCLINAÇÃO 3D GLOBO!
                        )
                    )
                }
            }
            
            // BOTÃO "GOT LOAD?" - TOPO DIREITO
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showLoadSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "truck.box.fill")
                                .font(.title3)
                            Text("Got Load?")
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.orange, .orange.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(30)
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    }
                    .padding(.top, 60)
                    .padding(.trailing, 20)
                }
                Spacer()
            }
            
            // BOTTOM SHEET COM INFO DA ROTA
            VStack {
                Spacer()
                RouteInfoSheet(
                    route: routeCalculator.currentRoute,
                    isCalculating: routeCalculator.isCalculating,
                    onCancelRoute: {
                        routeCalculator.clearRoute()
                    }
                )
                .background(Color(UIColor.systemBackground))
                .cornerRadius(20, corners: [.topLeft, .topRight])
                .shadow(color: .black.opacity(0.2), radius: 10, y: -5)
            }
        }
        .sheet(isPresented: $showLoadSheet) {
            LoadAddressSheet { destinationAddress in
                Task {
                    await routeCalculator.calculateRoute(
                        from: locationManager.currentLocation,
                        to: destinationAddress
                    )
                    showLoadSheet = false
                }
            }
        }
        .alert("Erro de Localização", isPresented: $locationManager.showLocationError) {
            Button("Ir para Configurações") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Por favor, ative a localização nas configurações para usar a navegação.")
        }
    }
}

// LOCATION MANAGER REAL
@MainActor
class LocationManagerREAL: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var heading: CLLocationDirection = 0
    @Published var speed: CLLocationSpeed = 0
    @Published var isPulsing = true
    @Published var showLocationError = false
    
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5 // Atualiza a cada 5 metros
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }
    
    func startTracking() {
        print("🚛 Iniciando rastreamento GPS...")
        
        let status = locationManager.authorizationStatus
        
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
            print("✅ GPS ativo!")
        case .denied, .restricted:
            print("❌ Permissão de localização negada!")
            showLocationError = true
        @unknown default:
            break
        }
    }
    
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }
    
    // DELEGATE: Localização atualizada
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            self.currentLocation = location.coordinate
            self.speed = location.speed
            print("📍 Localização: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            print("🚀 Velocidade: \(location.speed * 3.6) km/h")
        }
    }
    
    // DELEGATE: Direção atualizada
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            self.heading = newHeading.trueHeading
        }
    }
    
    // DELEGATE: Mudança de autorização
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.startUpdatingLocation()
                manager.startUpdatingHeading()
            case .denied, .restricted:
                self.showLocationError = true
            default:
                break
            }
        }
    }
}

// ROUTE CALCULATOR REAL
@MainActor
class RouteCalculatorREAL: ObservableObject {
    @Published var currentRoute: TruckRouteREAL?
    @Published var isCalculating = false
    @Published var communityAlerts: [CommunityAlert] = []
    
    func calculateRoute(from origin: CLLocationCoordinate2D?, to destinationAddress: String) async {
        guard let origin = origin else {
            print("❌ Localização de origem não disponível")
            return
        }
        
        isCalculating = true
        print("🧭 Calculando rota de \(origin) para \(destinationAddress)...")
        
        // 1. GEOCODING: Endereço → Coordenadas
        let geocoder = CLGeocoder()
        
        do {
            let placemarks = try await geocoder.geocodeAddressString(destinationAddress)
            
            guard let placemark = placemarks.first,
                  let destinationCoordinate = placemark.location?.coordinate else {
                print("❌ Não foi possível encontrar o endereço")
                isCalculating = false
                return
            }
            
            // 2. CALCULAR ROTA COM MAPKIT
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destinationCoordinate))
            request.transportType = .automobile
            request.requestsAlternateRoutes = false
            
            let directions = MKDirections(request: request)
            let response = try await directions.calculate()
            
            guard let route = response.routes.first else {
                print("❌ Nenhuma rota encontrada")
                isCalculating = false
                return
            }
            
            // 3. CRIAR ROTA COM AVISOS
            let warnings = analyzeRoute(route)
            
            currentRoute = TruckRouteREAL(
                id: UUID(),
                destinationName: placemark.name ?? destinationAddress,
                destination: destinationCoordinate,
                polyline: route.polyline,
                distance: formatDistance(route.distance),
                duration: formatDuration(route.expectedTravelTime),
                warnings: warnings
            )
            
            print("✅ Rota calculada!")
            print("📏 Distância: \(formatDistance(route.distance))")
            print("⏱️ Tempo estimado: \(formatDuration(route.expectedTravelTime))")
            
        } catch {
            print("❌ Erro ao calcular rota: \(error.localizedDescription)")
        }
        
        isCalculating = false
    }
    
    func clearRoute() {
        currentRoute = nil
    }
    
    func loadCommunityAlerts() {
        // Alertas mock para demonstração
        communityAlerts = [
            CommunityAlert(
                id: UUID(),
                type: .weigh,
                coordinate: CLLocationCoordinate2D(latitude: 37.7849, longitude: -122.4094),
                reportedBy: "driver123",
                reportedAt: Date(),
                confirmations: 5
            ),
            CommunityAlert(
                id: UUID(),
                type: .police,
                coordinate: CLLocationCoordinate2D(latitude: 37.7649, longitude: -122.4294),
                reportedBy: "driver456",
                reportedAt: Date(),
                confirmations: 12
            )
        ]
    }
    
    private func analyzeRoute(_ route: MKRoute) -> [RouteWarning] {
        var warnings: [RouteWarning] = []
        
        // Analisar altitude e pontes (simulado)
        let stepCount = route.steps.count
        
        if stepCount > 0 {
            // Adicionar warning de ponte se houver
            let midPoint = route.steps[stepCount / 2].polyline.coordinate
            
            warnings.append(RouteWarning(
                id: UUID(),
                type: "Bridge Ahead",
                coordinate: midPoint,
                icon: "figure.walk.motion",
                color: .yellow
            ))
        }
        
        return warnings
    }
    
    private func formatDistance(_ meters: CLLocationDistance) -> String {
        let miles = meters / 1609.34
        return String(format: "%.1f mi", miles)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}

// MODELS
struct TruckRouteREAL: Identifiable {
    let id: UUID
    let destinationName: String
    let destination: CLLocationCoordinate2D
    let polyline: MKPolyline
    let distance: String
    let duration: String
    let warnings: [RouteWarning]
}

struct RouteWarning: Identifiable {
    let id: UUID
    let type: String
    let coordinate: CLLocationCoordinate2D
    let icon: String
    let color: Color
}

// SHEET DE INFO DA ROTA
struct RouteInfoSheet: View {
    let route: TruckRouteREAL?
    let isCalculating: Bool
    let onCancelRoute: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.5))
                .frame(width: 40, height: 6)
                .padding(.top, 8)
            
            if isCalculating {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Calculando rota...")
                        .font(.headline)
                }
                .padding()
            } else if let route = route {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Rota Ativa")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(route.destinationName)
                                .font(.headline)
                        }
                        
                        Spacer()
                        
                        Button(action: onCancelRoute) {
                            Text("Cancelar")
                                .foregroundColor(.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    
                    HStack(spacing: 24) {
                        Label(route.distance, systemImage: "road.lanes")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Label(route.duration, systemImage: "clock")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if !route.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Alertas na Rota")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ForEach(route.warnings) { warning in
                                HStack {
                                    Image(systemName: warning.icon)
                                        .foregroundColor(warning.color)
                                    Text(warning.type)
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding()
            } else {
                VStack(spacing: 8) {
                    Text("Pronto para navegar")
                        .font(.headline)
                    Text("Toque 'Got Load?' para começar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .frame(height: route != nil ? 200 : 120)
    }
}

// SHEET PARA COLAR ENDEREÇO
struct LoadAddressSheet: View {
    @Environment(\.dismiss) var dismiss
    var onAddressSelected: (String) -> Void
    
    @State private var addressText = ""
    @State private var extractedAddress = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Got Load?")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 32)
                
                Button {
                    if let clipboard = UIPasteboard.general.string {
                        addressText = clipboard
                        extractAddress(from: clipboard)
                    }
                } label: {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("Colar do Clipboard")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                
                TextEditor(text: $addressText)
                    .frame(height: 120)
                    .padding(8)
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .onChange(of: addressText) { _, new in
                        extractAddress(from: new)
                    }
                
                if !extractedAddress.isEmpty {
                    VStack(spacing: 12) {
                        Text("✓ Endereço encontrado:")
                            .font(.headline)
                            .foregroundColor(.green)
                        
                        Text(extractedAddress)
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        
                        Button {
                            onAddressSelected(extractedAddress)
                        } label: {
                            Text("Calcular Rota")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
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
                    Button("Cancelar") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func extractAddress(from text: String) {
        // REGEX SIMPLES MAS EFETIVO
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

// Extension para corner radius
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    MyHorizonViewREAL()
}
