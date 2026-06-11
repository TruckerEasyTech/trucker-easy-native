import SwiftUI
import MapKit
import SwiftData

enum MapStyleOption: String, CaseIterable {
    case standard  = "Standard"
    case satellite = "Satellite"
    case hybrid    = "Hybrid"
    case globe     = "Globe"

    var mapStyle: MapStyle {
        switch self {
        case .standard:  return .standard(elevation: .realistic, showsTraffic: true)
        case .satellite: return .imagery(elevation: .realistic)
        case .hybrid:    return .hybrid(elevation: .realistic, showsTraffic: true)
        case .globe:     return .hybrid(elevation: .realistic, showsTraffic: false)  // closest to globe in SwiftUI Map
        }
    }

    var icon: String {
        switch self {
        case .standard:  return "map"
        case .satellite: return "globe.americas.fill"
        case .hybrid:    return "map.fill"
        case .globe:     return "globe"
        }
    }
}

struct MapView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var geofences: [GeofenceRegion]
    @Query private var trips: [Trip]

    @State private var locationManager = LocationManager()
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedMapStyle: MapStyleOption = .standard
    @State private var showingStylePicker = false
    @State private var showingRouteSheet = false
    @State private var destinationAddress = ""
    @State private var route: MKRoute?
    @State private var showingAddGeofence = false
    
    var activeTrip: Trip? {
        trips.first(where: { $0.isActive })
    }
    
    var currentLocationDescription: String {
        locationManager.currentLocation == nil ? "Locating..." : "Current Location"
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                Map(position: $position) {
                    // Current location
                    if let location = locationManager.currentLocation {
                        Annotation("Your Location", coordinate: location.coordinate) {
                            ZStack {
                                Circle()
                                    .fill(.blue.opacity(0.3))
                                    .frame(width: 40, height: 40)
                                
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 16, height: 16)
                                    .overlay {
                                        Circle()
                                            .stroke(.white, lineWidth: 2)
                                    }
                            }
                        }
                    }
                    
                    // Geofences
                    ForEach(geofences.filter { $0.isActive }) { geofence in
                        MapCircle(center: geofence.coordinate, radius: geofence.radius)
                            .foregroundStyle(.blue.opacity(0.2))
                            .stroke(.blue, lineWidth: 2)
                        
                        Annotation(geofence.name, coordinate: geofence.coordinate) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.red)
                                .font(.title)
                        }
                    }
                    
                    // Route
                    if let route = route {
                        MapPolyline(route.polyline)
                            .stroke(.blue, lineWidth: 5)
                    }
                }
                .mapStyle(selectedMapStyle.mapStyle)
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
                
                // Map Style Picker Button
                VStack(spacing: 12) {
                    Button(action: { showingStylePicker.toggle() }) {
                        Image(systemName: "map")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    
                    if showingStylePicker {
                        VStack(spacing: 8) {
                            MapStyleButton(title: "Standard", icon: "map", isSelected: selectedMapStyle == .standard) {
                                selectedMapStyle = .standard
                            }
                            MapStyleButton(title: "Satellite", icon: "camera.aperture", isSelected: selectedMapStyle == .satellite) {
                                selectedMapStyle = .satellite
                            }
                            MapStyleButton(title: "Hybrid", icon: "map.fill", isSelected: selectedMapStyle == .hybrid) {
                                selectedMapStyle = .hybrid
                            }
                            MapStyleButton(title: "Globe 3D", icon: "globe.americas.fill", isSelected: selectedMapStyle == .globe) {
                                selectedMapStyle = .globe
                            }
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .shadow(radius: 4)
                    }
                }
                .padding()
            }
            .navigationTitle("Map")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button(action: centerOnCurrentLocation) {
                            Label("My Location", systemImage: "location.fill")
                        }
                        
                        Button(action: { showingRouteSheet = true }) {
                            Label("Get Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                        }
                        
                        Button(action: { showingAddGeofence = true }) {
                            Label("Add Geofence", systemImage: "mappin.circle")
                        }
                        
                        Divider()
                        
                        Button(action: { selectedMapStyle = .standard }) {
                            Label("Standard Map", systemImage: "map")
                        }

                        Button(action: { selectedMapStyle = .satellite }) {
                            Label("Satellite View", systemImage: "globe.americas.fill")
                        }

                        Button(action: { selectedMapStyle = .hybrid }) {
                            Label("Hybrid View", systemImage: "map.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingRouteSheet = true }) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                }
            }
            .sheet(isPresented: $showingRouteSheet) {
                NavigationRouteSheet(
                    locationManager: locationManager,
                    onRouteCalculated: { calculatedRoute in
                        route = calculatedRoute
                        showingRouteSheet = false
                    }
                )
            }
            .sheet(isPresented: $showingAddGeofence) {
                AddGeofenceView(locationManager: locationManager)
            }
            .onAppear {
                locationManager.requestPermission()
                locationManager.startTracking()
                centerOnCurrentLocation()
            }
            .onDisappear {
                locationManager.stopTracking()
            }
        }
    }
    
    private func centerOnCurrentLocation() {
        if let location = locationManager.currentLocation {
            position = .region(MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))
        }
    }
}

struct MapStyleButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .foregroundColor(isSelected ? .blue : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
    }
}

struct NavigationRouteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let locationManager: LocationManager
    let onRouteCalculated: (MKRoute) -> Void
    
    @State private var destination = ""
    @State private var isCalculating = false
    @State private var errorMessage: String?
    
    var startingLocation: String {
        locationManager.currentLocation == nil ? "Locating..." : "Current Location"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Route") {
                    LabeledContent("From") {
                        Text(startingLocation)
                            .foregroundColor(.secondary)
                    }
                    
                    TextField("Destination", text: $destination)
                        .autocapitalization(.words)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
                
                Section {
                    Button(action: calculateRoute) {
                        HStack {
                            Spacer()
                            if isCalculating {
                                ProgressView()
                            } else {
                                Text("Calculate Route")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(destination.isEmpty || isCalculating)
                }
            }
            .navigationTitle("Get Directions")
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
    
    private func calculateRoute() {
        guard let currentLocation = locationManager.currentLocation else {
            errorMessage = "Current location not available"
            return
        }
        
        isCalculating = true
        errorMessage = nil
        
        Task {
            defer {
                Task { @MainActor in
                    isCalculating = false
                }
            }
            do {
                // Use MKLocalSearch for geocoding (recommended for iOS 26+)
                let searchRequest = MKLocalSearch.Request()
                searchRequest.naturalLanguageQuery = destination
                let search = MKLocalSearch(request: searchRequest)
                let searchResponse = try await search.start()

                guard let destItem = searchResponse.mapItems.first else {
                    await MainActor.run {
                        errorMessage = "Could not find destination"
                    }
                    return
                }

                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation.coordinate))
                request.destination = destItem
                request.transportType = .automobile
                
                let directions = MKDirections(request: request)
                let response = try await directions.calculate()
                
                if let route = response.routes.first {
                    await MainActor.run {
                        onRouteCalculated(route)
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Error calculating route: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct AddGeofenceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let locationManager: LocationManager
    
    @State private var name = ""
    @State private var radius = 1000.0
    @State private var notifyOnEntry = true
    @State private var notifyOnExit = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Geofence Details") {
                    TextField("Name", text: $name)
                    
                    VStack(alignment: .leading) {
                        Text("Radius: \(Int(radius))m")
                            .font(.subheadline)
                        Slider(value: $radius, in: 100...5000, step: 100)
                    }
                    
                    if locationManager.currentLocation != nil {
                        LabeledContent("Location") {
                            Text("Current GPS fix")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Notifications") {
                    Toggle("Notify on Entry", isOn: $notifyOnEntry)
                    Toggle("Notify on Exit", isOn: $notifyOnExit)
                }
            }
            .navigationTitle("New Geofence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveGeofence()
                    }
                    .disabled(name.isEmpty || locationManager.currentLocation == nil)
                }
            }
        }
    }
    
    private func saveGeofence() {
        guard let location = locationManager.currentLocation else { return }
        
        let geofence = GeofenceRegion(
            name: name,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            radius: radius,
            notifyOnEntry: notifyOnEntry,
            notifyOnExit: notifyOnExit
        )
        
        modelContext.insert(geofence)
        dismiss()
    }
}

#Preview {
    MapView()
        .modelContainer(for: [GeofenceRegion.self, Trip.self], inMemory: true)
}
