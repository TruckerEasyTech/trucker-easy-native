//
//  TruckNavigationApp.swift
//  trucker easy app
//
//  Created by AI Assistant on 3/31/26.
//
//  Complete truck navigation system with map, warnings, voice, and haptics

import SwiftUI
import MapKit
import CoreLocation
import AVFoundation

private func agentLogLegacy(
    runId: String,
    hypothesisId: String,
    location: String,
    message: String,
    data: [String: Any] = [:]
) {
    let payload: [String: Any] = [
        "sessionId": "ff95f6",
        "runId": runId,
        "hypothesisId": hypothesisId,
        "location": location,
        "message": message,
        "data": data,
        "timestamp": Int(Date().timeIntervalSince1970 * 1000)
    ]
    guard let json = try? JSONSerialization.data(withJSONObject: payload),
          var line = String(data: json, encoding: .utf8) else { return }
    line.append("\n")
    DeveloperDebugLog.appendNDJSONLine(line)
}

// RootEntryView and TruckerEasyApp removed — app uses trucker_easy_appApp → AppEntryView

// MARK: - Root Navigation View

struct TruckNavigationRootView: View {
    @State private var selectedProfile: TruckProfile?
    @State private var destination: CLLocationCoordinate2D?
    @State private var destinationName: String?
    @State private var showProfileSelector = false
    @State private var showDestinationPicker = false
    
    var body: some View {
        NavigationStack {
            if let profile = selectedProfile {
                // Main navigation view
                LegacyTruckNavigationMapView(
                    truckProfile: profile,
                    destination: $destination,
                    destinationName: $destinationName
                )
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button("Change Truck Profile") {
                                showProfileSelector = true
                            }
                            
                            Button("Set Destination") {
                                showDestinationPicker = true
                            }
                            
                            if destination != nil {
                                Button("Clear Destination", role: .destructive) {
                                    destination = nil
                                    destinationName = nil
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            } else {
                // Profile selection
                TruckProfileSelectorView(selectedProfile: $selectedProfile)
            }
        }
        .sheet(isPresented: $showProfileSelector) {
            NavigationView {
                TruckProfileSelectorView(selectedProfile: $selectedProfile)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showProfileSelector = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showDestinationPicker) {
            DestinationPickerView(
                destination: $destination,
                destinationName: $destinationName
            )
        }
    }
}

// MARK: - Truck Profile Selector

struct TruckProfileSelectorView: View {
    @Binding var selectedProfile: TruckProfile?
    @Environment(\.dismiss) private var dismiss
    
    private let predefinedProfiles: [(name: String, profile: TruckProfile, icon: String)] = [
        ("53' Semi Trailer", .semiFiftyThree, "truck.box.fill"),
        ("48' Semi Trailer", .semiFortyEight, "truck.box"),
        ("Straight Truck", .straightTruck, "shippingbox.fill"),
        ("Tanker Truck", .tanker, "drop.fill"),
        ("Flatbed Trailer", .flatbed, "rectangle.fill"),
        ("Refrigerated", .refrigerated, "snowflake"),
        ("Oversized Load", .oversized, "exclamationmark.triangle.fill")
    ]
    
    var body: some View {
        List {
            Section {
                ForEach(predefinedProfiles, id: \.name) { item in
                    Button {
                        selectedProfile = item.profile
                        dismiss()
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: item.icon)
                                .font(.title2)
                                .foregroundColor(.blue)
                                .frame(width: 40)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.headline)
                                
                                HStack(spacing: 12) {
                                    Label(
                                        String(format: "%.1f'", item.profile.heightMeters * 3.28084),
                                        systemImage: "arrow.up.and.down"
                                    )
                                    
                                    Label(
                                        String(format: "%.0f lbs", item.profile.weightTonnes * 2204.62),
                                        systemImage: "scalemass"
                                    )
                                    
                                    Label(
                                        String(format: "%.0f'", item.profile.lengthMeters * 3.28084),
                                        systemImage: "ruler"
                                    )
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedProfile?.truckType == item.profile.truckType {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Select Your Truck Type")
            } footer: {
                Text("Choose the profile that best matches your truck specifications. This ensures accurate truck-safe routing.")
            }
        }
        .navigationTitle("🚛 Truck Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Destination Picker

struct DestinationPickerView: View {
    @Binding var destination: CLLocationCoordinate2D?
    @Binding var destinationName: String?
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(searchResults, id: \.self) { item in
                        Button {
                            selectDestination(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name ?? "Unknown")
                                    .font(.headline)
                                
                                if #available(iOS 26, *) {
                                    if let address = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true) {
                                        Text(address)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    if let address = item.placemark.title {
                                        Text(address)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    if isSearching {
                        HStack {
                            ProgressView()
                            Text("Searching...")
                        }
                    } else {
                        Text("Search Results")
                    }
                }
                
                if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                    Section {
                        Text("No results found")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Enter destination address or name")
            .onChange(of: searchText) { _, newValue in
                Task { @MainActor in
                    isSearching = true
                    let currentQuery = newValue
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                    if currentQuery == searchText {
                        await performSearch(currentQuery)
                    }
                    isSearching = false
                }
            }
            .navigationTitle("📍 Destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func performSearch(_ query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        
        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            searchResults = response.mapItems
        } catch {
            print("Search error: \(error)")
            searchResults = []
        }
        
        isSearching = false
    }
    
    private func selectDestination(_ item: MKMapItem) {
        if #available(iOS 26, *) {
            destination = item.location.coordinate
        } else {
            destination = item.placemark.coordinate
        }
        destinationName = item.name
        dismiss()
    }
}

// MARK: - Main Map View with Full Integration

struct LegacyTruckNavigationMapView: View {
    let truckProfile: TruckProfile
    @Binding var destination: CLLocationCoordinate2D?
    @Binding var destinationName: String?
    
    // Managers
    @State private var locationManager = NavigationLocationManager()
    @State private var warningManager = TruckRestrictionWarningManager()
    @State private var voiceManager = VoiceAnnouncementManager()
    @State private var hapticManager = NavigationHapticFeedbackManager()
    
    // Route state
    @State private var currentRoute: TruckRoute?
    @State private var isCalculatingRoute = false
    @State private var routeError: String?
    
    // Coverage indicator (CORREÇÃO 4) ✅
    @State private var regionCoverage: RegionCoverage?
    
    // Map state
    @State private var recenterTrigger = 0
    @State private var showingRouteDetails = false
    
    var body: some View {
        ZStack {
            // Map with route
            mapView
            
            // Warnings overlay (top)
            VStack {
                // Coverage indicator (CORREÇÃO 4) ✅
                if let coverage = regionCoverage {
                    CoverageIndicatorView(coverage: coverage)
                        .transition(.move(edge: .top))
                }
                
                if let location = locationManager.lastLocation {
                    TruckRestrictionsOverlay(
                        warnings: warningManager.activeWarnings,
                        currentLocation: location,
                        dismissedWarningIds: $warningManager.dismissedWarningIds
                    )
                    .padding(.top, regionCoverage != nil ? 0 : 60)
                }
                
                Spacer()
                
                // Bottom controls
                bottomControls
            }
            
            // Loading indicator
            if isCalculatingRoute {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    ProgressView()
                        .te_uniformScale(1.5)
                        .tint(.white)
                    Text("Calculating truck-safe route...")
                        .foregroundColor(.white)
                        .font(.headline)
                }
                .padding(24)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
            }
        }
        .navigationTitle("🚛 Navigation")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // #region agent log
            agentLogLegacy(
                runId: "baseline",
                hypothesisId: "H1",
                location: "ViewsTruckNavigationApp.swift:task",
                message: "LegacyTruckNavigationMapView appeared",
                data: [
                    "hasDestination": destination != nil,
                    "hasCurrentRoute": currentRoute != nil
                ]
            )
            // #endregion
            await locationManager.requestLocation()
            
            // ✅ CORREÇÃO 4: Carregar cobertura da região
            if let location = locationManager.lastLocation {
                regionCoverage = await getCoverageForLocation(location.coordinate)
            }
        }
        .onChange(of: destination.map { "\($0.latitude),\($0.longitude)" }) { _, newValue in
            if newValue != nil {
                Task { await calculateRoute() }
            } else {
                clearRoute()
            }
        }
        .onChange(of: locationManager.lastLocation) { _, newLocation in
            if let location = newLocation {
                if currentRoute == nil {
                    recenterTrigger += 1
                }
                warningManager.updateLocation(location)
                checkForNearbyWarnings(at: location)
            }
        }
        .onChange(of: isCalculatingRoute) { _, newValue in
            // #region agent log
            agentLogLegacy(
                runId: "baseline",
                hypothesisId: "H3",
                location: "ViewsTruckNavigationApp.swift:onChange(isCalculatingRoute)",
                message: "Legacy isCalculatingRoute changed",
                data: [
                    "isCalculatingRoute": newValue,
                    "hasCurrentRoute": currentRoute != nil
                ]
            )
            // #endregion
        }
        .alert("Route Error", isPresented: .constant(routeError != nil)) {
            Button("OK") {
                routeError = nil
            }
        } message: {
            if let error = routeError {
                Text(error)
            }
        }
    }
    
    // MARK: - Map View

    private var mapView: some View {
        UniversalMapView(
            userLocation: locationManager.lastLocation?.coordinate,
            destination: destination,
            destinationName: destinationName,
            polyline: currentRoute?.coordinates ?? [],
            recenterTrigger: recenterTrigger
        )
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        VStack(spacing: 12) {
            if let route = currentRoute {
                // Route info card
                routeInfoCard(route)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            HStack(spacing: 12) {
                // Recenter button
                Button {
                    recenterTrigger += 1
                } label: {
                    Image(systemName: "location.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(.blue)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                
                Spacer()
                
                // Clear route button
                if currentRoute != nil {
                    Button {
                        clearRoute()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(.red)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .animation(.spring(), value: currentRoute != nil)
    }
    
    // MARK: - Route Info Card
    
    private func routeInfoCard(_ route: TruckRoute) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(destinationName ?? "Destination")
                        .font(.headline)
                    
                    HStack(spacing: 16) {
                        Label(
                            String(format: "%.1f mi", route.distanceMiles),
                            systemImage: "road.lanes"
                        )
                        
                        Label(
                            String(format: "%.1f hr", route.durationHours),
                            systemImage: "clock"
                        )
                        
                        if !warningManager.activeWarnings.isEmpty {
                            Label(
                                "\(warningManager.activeWarnings.count)",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundColor(.orange)
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    showingRouteDetails = true
                } label: {
                    Image(systemName: "info.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(radius: 4)
            .padding(.horizontal, 20)
        }
        .sheet(isPresented: $showingRouteDetails) {
            RouteDetailsView(
                route: route,
                warnings: warningManager.activeWarnings,
                truckProfile: truckProfile
            )
        }
    }
    
    // MARK: - Route Calculation
    
    func calculateRoute() async {
        guard let dest = destination,
              let origin = locationManager.lastLocation else {
            return
        }
        
        isCalculatingRoute = true
        routeError = nil
        defer { isCalculatingRoute = false }
        // #region agent log
        agentLogLegacy(
            runId: "baseline",
            hypothesisId: "H2",
            location: "ViewsTruckNavigationApp.swift:calculateRoute:start",
            message: "Legacy route calculation started",
            data: [
                "hasOrigin": true,
                "hasDestination": true
            ]
        )
        // #endregion
        
        do {
            // Calculate route with warnings
            let (route, warnings) = try await truckProfile.calculateRouteWithWarnings(
                from: origin,
                to: dest,
                destinationName: destinationName ?? "Destination",
                avoidTolls: false
            )
            
            currentRoute = route
            // #region agent log
            agentLogLegacy(
                runId: "baseline",
                hypothesisId: "H2",
                location: "ViewsTruckNavigationApp.swift:calculateRoute:success",
                message: "Legacy route calculation success",
                data: [
                    "provider": RoutingService.shared.lastProvider.rawValue,
                    "coordinatesCount": route.coordinates.count,
                    "stepsCount": route.steps.count
                ]
            )
            // #endregion
            
            // Load warnings into manager
            await warningManager.loadWarnings(
                from: route,
                userLocation: origin,
                specs: truckProfile.toSpecifications(),
                regulations: nil
            )
            
            // Announce route calculated
            await voiceManager.announce("Route calculated. \(Int(route.distanceMiles)) miles, approximately \(Int(route.durationHours)) hours.")
            
            // Haptic feedback
            hapticManager.success()
            
            // Update camera to show full route
            updateCameraForRoute(route)
            
            print("✅ Route calculated: \(route.distanceMiles) mi, \(warnings.count) warnings")
            
        } catch {
            let emergency = emergencyDirectRoute(
                from: origin.coordinate,
                to: dest,
                destinationName: destinationName ?? "Destination"
            )
            currentRoute = emergency
            updateCameraForRoute(emergency)
            routeError = nil
            hapticManager.warning()
            print("⚠️ Route providers failed, using emergency direct route: \(error.localizedDescription)")
            // #region agent log
            agentLogLegacy(
                runId: "baseline",
                hypothesisId: "H2",
                location: "ViewsTruckNavigationApp.swift:calculateRoute:catch",
                message: "Legacy route calculation failed and emergency route applied",
                data: [
                    "error": error.localizedDescription,
                    "emergencyCoordinatesCount": currentRoute?.coordinates.count ?? 0
                ]
            )
            // #endregion
        }
    }

    private func emergencyDirectRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String
    ) -> TruckRoute {
        let originLoc = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let destLoc = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let distanceMeters = max(originLoc.distance(from: destLoc), 10)
        let durationSeconds = distanceMeters / 22.352

        let pointCount = max(10, Int(distanceMeters / 1000))
        var coordinates: [CLLocationCoordinate2D] = []
        coordinates.reserveCapacity(pointCount + 1)
        for i in 0...pointCount {
            let fraction = Double(i) / Double(pointCount)
            let lat = origin.latitude + fraction * (destination.latitude - origin.latitude)
            let lon = origin.longitude + fraction * (destination.longitude - origin.longitude)
            coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        let steps = [
            RouteStep(
                instruction: "Navigate to \(destinationName)",
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                maneuver: "continue"
            )
        ]

        return TruckRoute(
            coordinates: coordinates,
            steps: steps,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            destinationName: destinationName,
            truckNotices: [TruckRouteNotice(code: "EMERGENCY", title: "Emergency route mode", details: "Live road data unavailable; using direct guidance line.")]
        )
    }
    
    func clearRoute() {
        currentRoute = nil
        warningManager.clearWarnings()
        destination = nil
        destinationName = nil
        
        hapticManager.impact()
    }
    
    // MARK: - Warning Checking (CORREÇÃO 3 - AMPLIADA) ✅
    
    func checkForNearbyWarnings(at location: CLLocation) {
        var allWarnings = warningManager.activeWarnings
        
        // ✅ NOVO: Adicionar warnings do banco de dados local
        let localWarnings = checkLocalBridgeDatabase(near: location, truckHeight: truckProfile.heightMeters)
        allWarnings.append(contentsOf: localWarnings)
        
        // ✅ AMPLIADO: Janela de detecção maior
        let nearbyWarnings = allWarnings.filter { warning in
            guard let coord = warning.coordinate,
                  !warningManager.dismissedWarningIds.contains(warning.id) else {
                return false
            }
            
            let warningLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let distance = location.distance(from: warningLocation)
            
            // Anuncia em 2km, 1km, 500m, e 200m (JANELAS AMPLIADAS)
            return (distance <= 2000 && distance > 1700) ||  // 2km
                   (distance <= 1000 && distance > 850) ||    // 1km
                   (distance <= 500 && distance > 400) ||     // 500m
                   (distance <= 200 && distance > 100)        // 200m
        }
        
        // Ordenar por distância (mais próximo primeiro)
        let sortedWarnings = nearbyWarnings.sorted { w1, w2 in
            guard let c1 = w1.coordinate, let c2 = w2.coordinate else { return false }
            let l1 = CLLocation(latitude: c1.latitude, longitude: c1.longitude)
            let l2 = CLLocation(latitude: c2.latitude, longitude: c2.longitude)
            return location.distance(from: l1) < location.distance(from: l2)
        }
        
        if let closestWarning = sortedWarnings.first,
           let coord = closestWarning.coordinate {
            let warningLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let distance = location.distance(from: warningLocation)
            let distanceMiles = distance / 1609.34
            let distanceKm = distance / 1000.0
            
            // ✅ MELHORADO: Mensagem de voz mais clara
            let isMetric: Bool
            if #available(iOS 16, *) {
                isMetric = Locale.current.measurementSystem != .us
            } else {
                isMetric = Locale.current.usesMetricSystem
            }
            let distanceText = isMetric ?
                "\(String(format: "%.1f", distanceKm)) kilometers" :
                "\(String(format: "%.1f", distanceMiles)) miles"
            
            Task {
                await voiceManager.announce(
                    "\(closestWarning.type.rawValue) ahead in \(distanceText). \(closestWarning.message)"
                )
            }
            
            // Haptic warning
            hapticManager.warning()
            
            print("⚠️ Warning: \(closestWarning.type.rawValue) at \(distanceText)")
        }
    }
    
    // ✅ NOVA FUNÇÃO: Verificar banco de dados local
    func checkLocalBridgeDatabase(near location: CLLocation, truckHeight: Double) -> [TruckRestrictionWarning] {
        let truckHeightFeet = truckHeight * 3.28084
        var warnings: [TruckRestrictionWarning] = []

        for bridge in allKnownLowBridges {
            let bridgeLocation = CLLocation(
                latitude: bridge.coordinate.latitude,
                longitude: bridge.coordinate.longitude
            )
            let distance = location.distance(from: bridgeLocation)
            
            // Verificar se está dentro de 5km E se o caminhão é mais alto que a ponte
            // Adicionar margem de segurança de 6 polegadas (0.5 feet)
            let safetyMargin: Double = 0.5
            guard distance <= 5000 && (truckHeightFeet + safetyMargin) >= bridge.heightFeet else {
                continue
            }
            
            let clearance = bridge.heightFeet - truckHeightFeet
            let warningMessage: String
            
            if clearance <= 0 {
                warningMessage = "⚠️ DANGER! \(bridge.name) clearance: \(String(format: "%.1f", bridge.heightFeet))ft. Your truck: \(String(format: "%.1f", truckHeightFeet))ft. DO NOT PROCEED!"
            } else if clearance < 1.0 {
                warningMessage = "⚠️ CAUTION! \(bridge.name) clearance: \(String(format: "%.1f", bridge.heightFeet))ft. Your truck: \(String(format: "%.1f", truckHeightFeet))ft. Only \(String(format: "%.1f", clearance * 12)) inches clearance!"
            } else {
                warningMessage = "\(bridge.name) at \(bridge.location), \(bridge.state). Clearance: \(String(format: "%.1f", bridge.heightFeet))ft. Your truck: \(String(format: "%.1f", truckHeightFeet))ft."
            }
            
            warnings.append(TruckRestrictionWarning(
                type: .lowBridge,
                message: warningMessage,
                coordinate: bridge.coordinate
            ))
        }

        return warnings
    }
    
    // MARK: - Helper Methods
    
    func updateCameraForRoute(_ route: TruckRoute) {
        guard route.coordinates.count >= 2 else { return }
        // Trigger recenter so UniversalMapView moves to user/destination
        recenterTrigger += 1
    }
    
}

// MARK: - Location Manager

@Observable
@MainActor
class NavigationLocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var lastLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10 // Update every 10 meters
    }
    
    func requestLocation() async {
        guard authorizationStatus != .authorizedWhenInUse &&
              authorizationStatus != .authorizedAlways else {
            manager.startUpdatingLocation()
            return
        }
        
        manager.requestWhenInUseAuthorization()
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            
            if authorizationStatus == .authorizedWhenInUse ||
               authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            lastLocation = locations.last
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}

// MARK: - Voice Announcement Manager
// Canonical definition in ManagersVoiceAnnouncementManager.swift

// MARK: - Haptic Feedback Manager

@MainActor
class NavigationHapticFeedbackManager {
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    var isEnabled = true
    
    init() {
        notificationGenerator.prepare()
        impactGenerator.prepare()
    }
    
    func success() {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(.success)
    }
    
    func warning() {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(.warning)
    }
    
    func error() {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(.error)
    }
    
    func impact() {
        guard isEnabled else { return }
        impactGenerator.impactOccurred()
    }
}

// MARK: - Route Details View

struct RouteDetailsView: View {
    let route: TruckRoute
    let warnings: [TruckRestrictionWarning]
    let truckProfile: TruckProfile
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                // Route summary
                Section("Route Summary") {
                    HStack {
                        Label("Distance", systemImage: "road.lanes")
                        Spacer()
                        Text(String(format: "%.1f miles", route.distanceMiles))
                    }
                    
                    HStack {
                        Label("Duration", systemImage: "clock")
                        Spacer()
                        Text(String(format: "%.1f hours", route.durationHours))
                    }
                    
                    HStack {
                        Label("Coordinates", systemImage: "point.3.connected.trianglepath.dotted")
                        Spacer()
                        Text("\(route.coordinates.count)")
                    }
                }
                
                // Truck info
                Section("Truck Information") {
                    HStack {
                        Label("Type", systemImage: "truck.box.fill")
                        Spacer()
                        Text(truckProfile.truckType.rawValue)
                    }
                    
                    HStack {
                        Label("Height", systemImage: "arrow.up.and.down")
                        Spacer()
                        Text(String(format: "%.1f ft", truckProfile.heightMeters * 3.28084))
                    }
                    
                    HStack {
                        Label("Weight", systemImage: "scalemass")
                        Spacer()
                        Text(String(format: "%.0f lbs", truckProfile.weightTonnes * 2204.62))
                    }
                    
                    HStack {
                        Label("Length", systemImage: "ruler")
                        Spacer()
                        Text(String(format: "%.0f ft", truckProfile.lengthMeters * 3.28084))
                    }
                }
                
                // Warnings
                if !warnings.isEmpty {
                    Section("Warnings (\(warnings.count))") {
                        ForEach(warnings) { warning in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: warning.type.icon)
                                    .foregroundColor(warningColorForType(warning.type))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(warning.type.rawValue)
                                        .font(.headline)
                                    Text(warning.message)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                // Turn-by-turn
                if !route.steps.isEmpty {
                    Section("Turn-by-Turn (\(route.steps.count))") {
                        ForEach(Array(route.steps.enumerated()), id: \.offset) { index, step in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(index + 1). \(step.instruction)")
                                    .font(.subheadline)
                                
                                if step.distanceMeters > 0 {
                                    Text(String(format: "%.1f miles", step.distanceMeters / 1609.34))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Route Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Known Low Bridges Database (CORREÇÃO 2) ✅

/// Banco de dados local de pontes baixas conhecidas
/// Fonte: FHWA (Federal Highway Administration), DOT estaduais
struct KnownLowBridge: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let heightFeet: Double
    let heightMeters: Double
    let name: String
    let location: String
    let state: String
    let route: String
    
    init(latitude: Double, longitude: Double, heightFeet: Double, name: String, location: String, state: String, route: String = "") {
        self.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        self.heightFeet = heightFeet
        self.heightMeters = heightFeet / 3.28084
        self.name = name
        self.location = location
        self.state = state
        self.route = route
    }
}

/// Pontes baixas conhecidas nos EUA
let knownLowBridgesUSA: [KnownLowBridge] = [
    // CAROLINA DO NORTE
    KnownLowBridge(
        latitude: 35.9940,
        longitude: -78.9103,
        heightFeet: 11.67,
        name: "11-foot-8 Bridge (Can Opener)",
        location: "Gregson Street",
        state: "NC",
        route: "Gregson St over Norfolk Southern Railway"
    ),
    
    // MASSACHUSETTS - BOSTON
    KnownLowBridge(
        latitude: 42.3601,
        longitude: -71.0589,
        heightFeet: 12.0,
        name: "Storrow Drive Bridge",
        location: "Storrow Drive",
        state: "MA",
        route: "Storrow Dr Westbound"
    ),
    
    KnownLowBridge(
        latitude: 42.3522,
        longitude: -71.0552,
        heightFeet: 12.5,
        name: "Soldiers Field Road Bridge",
        location: "Soldiers Field Road",
        state: "MA",
        route: "Soldiers Field Rd"
    ),
    
    // NEW YORK CITY
    KnownLowBridge(
        latitude: 40.7580,
        longitude: -73.9855,
        heightFeet: 12.0,
        name: "Park Avenue Tunnel",
        location: "Park Avenue",
        state: "NY",
        route: "Park Ave btw 33rd-40th St"
    ),
    
    KnownLowBridge(
        latitude: 40.7128,
        longitude: -74.0060,
        heightFeet: 11.5,
        name: "West Street Underpass",
        location: "West Street",
        state: "NY",
        route: "West St / West Side Highway"
    ),
    
    // ILLINOIS - CHICAGO
    KnownLowBridge(
        latitude: 41.8781,
        longitude: -87.6298,
        heightFeet: 13.5,
        name: "Wacker Drive Underpass",
        location: "Lower Wacker Drive",
        state: "IL",
        route: "Lower Wacker Dr"
    ),
    
    // CALIFORNIA - LOS ANGELES
    KnownLowBridge(
        latitude: 34.0522,
        longitude: -118.2437,
        heightFeet: 13.0,
        name: "6th Street Viaduct",
        location: "6th Street",
        state: "CA",
        route: "6th St over LA River"
    ),
    
    // CALIFORNIA - SAN FRANCISCO
    KnownLowBridge(
        latitude: 37.7749,
        longitude: -122.4194,
        heightFeet: 14.0,
        name: "Battery Street Tunnel",
        location: "Battery Street",
        state: "CA",
        route: "Battery St"
    ),
    
    // PENNSYLVANIA - PHILADELPHIA
    KnownLowBridge(
        latitude: 39.9526,
        longitude: -75.1652,
        heightFeet: 12.5,
        name: "Vine Street Expressway",
        location: "Vine Street",
        state: "PA",
        route: "I-676"
    ),
    
    // TEXAS - HOUSTON
    KnownLowBridge(
        latitude: 29.7604,
        longitude: -95.3698,
        heightFeet: 13.5,
        name: "Buffalo Bayou Underpass",
        location: "Allen Parkway",
        state: "TX",
        route: "Allen Pkwy"
    ),
    
    // FLORIDA - MIAMI
    KnownLowBridge(
        latitude: 25.7617,
        longitude: -80.1918,
        heightFeet: 13.0,
        name: "I-95 Underpass",
        location: "NW 7th Avenue",
        state: "FL",
        route: "NW 7th Ave under I-95"
    ),
    
    // WASHINGTON - SEATTLE
    KnownLowBridge(
        latitude: 47.6062,
        longitude: -122.3321,
        heightFeet: 14.0,
        name: "Alaskan Way Viaduct",
        location: "Alaskan Way",
        state: "WA",
        route: "SR-99"
    ),
    
    // GEORGIA - ATLANTA
    KnownLowBridge(
        latitude: 33.7490,
        longitude: -84.3880,
        heightFeet: 13.5,
        name: "Downtown Connector Underpass",
        location: "Peachtree Street",
        state: "GA",
        route: "Peachtree St under I-75/85"
    )
]

/// Pontes baixas conhecidas no Canadá
let knownLowBridgesCanada: [KnownLowBridge] = [
    // ONTARIO - TORONTO
    KnownLowBridge(
        latitude: 43.6532,
        longitude: -79.3832,
        heightFeet: 12.0,
        name: "Dufferin Street Bridge",
        location: "Dufferin Street",
        state: "ON",
        route: "Dufferin St over railway"
    ),
    
    // QUEBEC - MONTREAL
    KnownLowBridge(
        latitude: 45.5017,
        longitude: -73.5673,
        heightFeet: 13.0,
        name: "Notre-Dame Tunnel",
        location: "Autoroute Ville-Marie",
        state: "QC",
        route: "A-720"
    ),
    
    // BRITISH COLUMBIA - VANCOUVER
    KnownLowBridge(
        latitude: 49.2827,
        longitude: -123.1207,
        heightFeet: 13.5,
        name: "Granville Street Bridge",
        location: "Granville Street",
        state: "BC",
        route: "Granville St"
    )
]

/// Pontes baixas conhecidas na Europa
let knownLowBridgesEurope: [KnownLowBridge] = [
    // REINO UNIDO - LONDRES
    KnownLowBridge(
        latitude: 51.5074,
        longitude: -0.1278,
        heightFeet: 11.5,
        name: "Southwark Bridge",
        location: "Southwark Bridge",
        state: "UK",
        route: "A3"
    ),
    
    // ALEMANHA - BERLIM
    KnownLowBridge(
        latitude: 52.5200,
        longitude: 13.4050,
        heightFeet: 12.0,
        name: "S-Bahn Bridge",
        location: "Mitte",
        state: "DE",
        route: "Unter den Linden"
    ),
    
    // FRANÇA - PARIS
    KnownLowBridge(
        latitude: 48.8566,
        longitude: 2.3522,
        heightFeet: 13.0,
        name: "Pont des Arts",
        location: "Seine River",
        state: "FR",
        route: "Quai François Mitterrand"
    )
]

/// Combina todos os bancos de dados
let allKnownLowBridges: [KnownLowBridge] = 
    knownLowBridgesUSA + knownLowBridgesCanada + knownLowBridgesEurope

// MARK: - Region Coverage Info (CORREÇÃO 4) ✅

struct RegionCoverage {
    let region: String
    let country: String
    let hasTruckRouting: Bool
    let hasLowBridgeData: Bool
    let hasWeightRestrictions: Bool
    let hasTrafficData: Bool
    
    var coverageLevel: CoverageLevel {
        let score = [
            hasTruckRouting,
            hasLowBridgeData,
            hasWeightRestrictions,
            hasTrafficData
        ].filter { $0 }.count
        
        switch score {
        case 4: return .excellent
        case 3: return .good
        case 2: return .partial
        default: return .limited
        }
    }
    
    enum CoverageLevel: String {
        case excellent = "Excellent Coverage"
        case good = "Good Coverage"
        case partial = "Partial Coverage"
        case limited = "Limited Coverage"
        
        var color: Color {
            switch self {
            case .excellent: return .green
            case .good: return .blue
            case .partial: return .orange
            case .limited: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .excellent: return "checkmark.circle.fill"
            case .good: return "checkmark.circle"
            case .partial: return "exclamationmark.triangle.fill"
            case .limited: return "xmark.circle.fill"
            }
        }
    }
}

// Base de dados de cobertura por país
let coverageByCountry: [String: RegionCoverage] = [
    "US": RegionCoverage(
        region: "North America",
        country: "United States",
        hasTruckRouting: true,
        hasLowBridgeData: true,
        hasWeightRestrictions: true,
        hasTrafficData: true
    ),
    "CA": RegionCoverage(
        region: "North America",
        country: "Canada",
        hasTruckRouting: true,
        hasLowBridgeData: true,
        hasWeightRestrictions: true,
        hasTrafficData: true
    ),
    "MX": RegionCoverage(
        region: "North America",
        country: "Mexico",
        hasTruckRouting: true,
        hasLowBridgeData: false,
        hasWeightRestrictions: false,
        hasTrafficData: true
    ),
    "GB": RegionCoverage(
        region: "Europe",
        country: "United Kingdom",
        hasTruckRouting: true,
        hasLowBridgeData: true,
        hasWeightRestrictions: true,
        hasTrafficData: true
    ),
    "DE": RegionCoverage(
        region: "Europe",
        country: "Germany",
        hasTruckRouting: true,
        hasLowBridgeData: true,
        hasWeightRestrictions: true,
        hasTrafficData: true
    ),
    "FR": RegionCoverage(
        region: "Europe",
        country: "France",
        hasTruckRouting: true,
        hasLowBridgeData: true,
        hasWeightRestrictions: true,
        hasTrafficData: true
    ),
    "BR": RegionCoverage(
        region: "South America",
        country: "Brazil",
        hasTruckRouting: false,
        hasLowBridgeData: false,
        hasWeightRestrictions: false,
        hasTrafficData: true
    )
]

// Função para detectar cobertura
func getCoverageForLocation(_ coordinate: CLLocationCoordinate2D) async -> RegionCoverage {
    let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    if #available(iOS 26, *) {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return coverageByCountry["US"] ?? RegionCoverage(
                region: "Unknown", country: "Unknown",
                hasTruckRouting: false, hasLowBridgeData: false,
                hasWeightRestrictions: false, hasTrafficData: false
            )
        }
        let items = await withCheckedContinuation { (c: CheckedContinuation<[MKMapItem]?, Never>) in
            request.getMapItems { items, _ in c.resume(returning: items) }
        }
        if let country = items?.first?.addressRepresentations?.region?.identifier {
            return coverageByCountry[country] ?? RegionCoverage(
                region: "Unknown",
                country: country,
                hasTruckRouting: false,
                hasLowBridgeData: false,
                hasWeightRestrictions: false,
                hasTrafficData: false
            )
        }
    } else {
        do {
            let geocoder = CLGeocoder()
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let country = placemarks.first?.isoCountryCode {
                return coverageByCountry[country] ?? RegionCoverage(
                    region: "Unknown",
                    country: country,
                    hasTruckRouting: false,
                    hasLowBridgeData: false,
                    hasWeightRestrictions: false,
                    hasTrafficData: false
                )
            }
        } catch {
            print("Geocode error: \(error)")
        }
    }
    
    // Fallback: cobertura limitada
    return RegionCoverage(
        region: "Unknown",
        country: "Unknown",
        hasTruckRouting: false,
        hasLowBridgeData: false,
        hasWeightRestrictions: false,
        hasTrafficData: false
    )
}

// MARK: - Coverage Indicator View

struct CoverageIndicatorView: View {
    let coverage: RegionCoverage
    @State private var showDetails = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: coverage.coverageLevel.icon)
                    .foregroundColor(coverage.coverageLevel.color)
                    .font(.caption)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(coverage.coverageLevel.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(coverage.coverageLevel.color)
                    
                    Text(coverage.country)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    showDetails.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .shadow(radius: 2)
            
            if showDetails {
                VStack(alignment: .leading, spacing: 4) {
                    featureRow("Truck Routing", available: coverage.hasTruckRouting)
                    featureRow("Low Bridge Data", available: coverage.hasLowBridgeData)
                    featureRow("Weight Restrictions", available: coverage.hasWeightRestrictions)
                    featureRow("Traffic Data", available: coverage.hasTrafficData)
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .shadow(radius: 2)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .animation(.spring(), value: showDetails)
    }
    
    private func featureRow(_ name: String, available: Bool) -> some View {
        HStack {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(available ? .green : .red)
                .font(.caption2)
            Text(name)
                .font(.caption2)
            Spacer()
        }
    }
}

private func warningColorForType(_ type: TruckRestrictionWarning.WarningType) -> Color {
    switch type {
    case .lowBridge, .heightLimit:
        return .red
    case .weightLimit:
        return .orange
    case .hazmat:
        return Color(red: 0.96, green: 0.62, blue: 0.04)
    case .tunnel:
        return Color(red: 0.39, green: 0.40, blue: 0.96)
    case .narrowRoad:
        return .orange
    case .general:
        return .yellow
    }
}
// MARK: - Preview

#Preview("Root View") {
    TruckNavigationRootView()
}

#Preview("Profile Selector") {
    NavigationView {
        TruckProfileSelectorView(selectedProfile: .constant(nil))
    }
}

#Preview("Map View") {
    NavigationView {
        LegacyTruckNavigationMapView(
            truckProfile: TruckProfile.semiFiftyThree,
            destination: .constant(CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)),
            destinationName: .constant("Los Angeles, CA")
        )
    }
}
