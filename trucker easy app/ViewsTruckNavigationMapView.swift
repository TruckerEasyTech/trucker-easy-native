//
//  TruckNavigationMapView.swift
//  trucker easy app
//
//  Created by AI Assistant on 3/31/26.
//
//  Complete truck navigation view with:
//  - Real-time truck-safe routing
//  - Smart warning system with lookahead
//  - Voice announcements
//  - Haptic feedback
//  - Map integration

import SwiftUI
import MapKit
import CoreLocation
import AVFoundation

// MARK: - Main Navigation View

struct TruckNavigationMapView: View {
    // State
    @State private var routingService = RoutingService.shared
    @State private var warningManager = TruckRestrictionWarningManager()
    @State private var locationManager = TruckLocationManager()
    @State private var voiceAnnouncer = VoiceAnnouncer()
    @State private var hapticFeedback = HapticFeedbackManager()
    
    @State private var currentRoute: TruckRoute?
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var isCalculating = false
    @State private var errorMessage: String?
    @State private var showRouteDetails = false
    
    // User settings
    let truckProfile: TruckProfile
    @State private var avoidTolls = false
    @State private var voiceEnabled = true
    @State private var hapticEnabled = true
    
    // Destination
    @Binding var destination: CLLocationCoordinate2D?
    @Binding var destinationName: String?
    
    var body: some View {
        ZStack {
            // Map
            mapView
            
            // Overlays
            VStack {
                // Warning overlay
                if let location = locationManager.currentLocation {
                    TruckRestrictionsOverlay(
                        warnings: warningManager.activeWarnings,
                        currentLocation: location,
                        dismissedWarningIds: $warningManager.dismissedWarningIds
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer()
                
                // Route summary bar (bottom)
                if let route = currentRoute {
                    routeSummaryBar(route)
                        .transition(.move(edge: .bottom))
                }
            }
            
            // Top controls
            VStack {
                topControlsBar
                Spacer()
            }
            
            // Loading overlay
            if isCalculating {
                loadingOverlay
            }
            
            // Error alert
            if let error = errorMessage {
                errorAlert(error)
            }
        }
        .onAppear {
            locationManager.startUpdating()
        }
        .onChange(of: destination) { _, newDestination in
            if newDestination != nil {
                Task { await calculateRoute() }
            }
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            if let location = newLocation {
                warningManager.updateLocation(location)
            }
        }
        .onChange(of: warningManager.activeWarnings) { _, warnings in
            handleNewWarnings(warnings)
        }
        .sheet(isPresented: $showRouteDetails) {
            if let route = currentRoute {
                RouteDetailsSheet(route: route, truckProfile: truckProfile)
            }
        }
    }
    
    // MARK: - Map View
    
    private var mapView: some View {
        Map(position: $mapCameraPosition) {
            // User location
            if let location = locationManager.currentLocation {
                Annotation("", coordinate: location.coordinate) {
                    Circle()
                        .fill(.blue)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(.white, lineWidth: 3)
                        )
                        .shadow(radius: 3)
                }
            }
            
            // Route polyline
            if let route = currentRoute {
                MapPolyline(coordinates: route.coordinates)
                    .stroke(.blue, lineWidth: 5)
            }
            
            // Destination marker
            if let dest = destination, let name = destinationName {
                Marker(name, coordinate: dest)
                    .tint(.red)
            }
            
            // Warning markers
            ForEach(warningManager.activeWarnings) { warning in
                if let coord = warning.coordinate,
                   !warningManager.dismissedWarningIds.contains(warning.id) {
                    Annotation("", coordinate: coord) {
                        Image(systemName: warning.type.icon)
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(colorForWarningType(warning.type))
                                    .shadow(radius: 3)
                            )
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
    }
    
    // MARK: - Top Controls
    
    private var topControlsBar: some View {
        HStack {
            // Settings button
            Menu {
                Toggle("🔊 Voice Announcements", isOn: $voiceEnabled)
                Toggle("📳 Haptic Feedback", isOn: $hapticEnabled)
                Toggle("🚫 Avoid Tolls", isOn: $avoidTolls)
                
                Divider()
                
                Button("📊 Route Details") {
                    showRouteDetails = true
                }
                
                if currentRoute != nil {
                    Button("🔄 Recalculate") {
                        Task { await calculateRoute() }
                    }
                }
            } label: {
                Image(systemName: "gear")
                    .font(.title2)
                    .foregroundColor(.primary)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            
            Spacer()
            
            // HERE API status indicator
            if RoutingService.shared.isAvailable {
                Label("Truck-Safe", systemImage: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
        }
        .padding()
    }
    
    // MARK: - Route Summary Bar
    
    private func routeSummaryBar(_ route: TruckRoute) -> some View {
        VStack(spacing: 8) {
            // Main info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(destinationName ?? "Destination")
                        .font(.headline)
                    
                    HStack(spacing: 16) {
                        Label(
                            String(format: "%.0f mi", route.distanceMiles),
                            systemImage: "road.lanes"
                        )
                        
                        Label(
                            String(format: "%.1f hrs", route.durationHours),
                            systemImage: "clock.fill"
                        )
                        
                        if !route.truckNotices.isEmpty {
                            Label(
                                "\(route.truckNotices.count)",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundColor(.orange)
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { showRouteDetails = true }) {
                    Image(systemName: "chevron.up")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
            }
            
            // Progress bar (optional - based on location along route)
            if let progress = calculateRouteProgress() {
                ProgressView(value: progress)
                    .tint(.blue)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(radius: 10)
        .padding()
    }
    
    // MARK: - Loading Overlay
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .te_uniformScale(1.5)
                    .tint(.white)
                
                Text("Calculating truck-safe route...")
                    .foregroundColor(.white)
                    .font(.headline)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }
    
    // MARK: - Error Alert
    
    private func errorAlert(_ message: String) -> some View {
        VStack {
            Spacer()
            
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .font(.subheadline)
                Spacer()
                Button("Dismiss") {
                    errorMessage = nil
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .padding()
        }
    }
    
    // MARK: - Route Calculation
    
    private func calculateRoute() async {
        guard let dest = destination,
              let destName = destinationName,
              let origin = locationManager.currentLocation else {
            errorMessage = "Location not available"
            return
        }
        
        isCalculating = true
        errorMessage = nil
        defer { isCalculating = false }
        
        do {
            print("🚛 [Navigation] Calculating route to \(destName)...")
            
            // Calculate route with warnings
            let (route, warnings) = try await truckProfile.calculateRouteWithWarnings(
                from: origin,
                to: dest,
                destinationName: destName,
                avoidTolls: avoidTolls
            )
            
            currentRoute = route
            
            // Load warnings into manager
            await warningManager.loadWarnings(
                from: route,
                userLocation: origin,
                specs: truckProfile.toSpecifications(),
                regulations: nil  // Auto-detect
            )
            
            // Center map on route
            if let firstCoord = route.coordinates.first,
               let lastCoord = route.coordinates.last {
                let region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: (firstCoord.latitude + lastCoord.latitude) / 2,
                        longitude: (firstCoord.longitude + lastCoord.longitude) / 2
                    ),
                    span: MKCoordinateSpan(
                        latitudeDelta: abs(firstCoord.latitude - lastCoord.latitude) * 1.5,
                        longitudeDelta: abs(firstCoord.longitude - lastCoord.longitude) * 1.5
                    )
                )
                mapCameraPosition = .region(region)
            }
            
            // Announce route calculated
            if voiceEnabled {
                voiceAnnouncer.announce(
                    "Route calculated. \(Int(route.distanceMiles)) miles, " +
                    "approximately \(Int(route.durationHours)) hours. " +
                    "\(warnings.count) truck restrictions detected."
                )
            }
            
            // Haptic feedback
            if hapticEnabled {
                hapticFeedback.success()
            }
            
            print("✅ [Navigation] Route calculated: \(route.distanceMiles) miles")
            print("✅ [Navigation] Warnings: \(warnings.count)")
            
        } catch {
            errorMessage = error.localizedDescription
            print("❌ [Navigation] Error: \(error)")
            
            if hapticEnabled {
                hapticFeedback.error()
            }
        }
    }
    
    // MARK: - Warning Callbacks
    
    @State private var lastAnnouncedWarningId: UUID?
    
    private func handleNewWarnings(_ warnings: [TruckRestrictionWarning]) {
        guard let location = locationManager.currentLocation else { return }
        
        // Find closest warning
        let sortedWarnings = warnings
            .filter { !warningManager.dismissedWarningIds.contains($0.id) }
            .sorted { w1, w2 in
                let d1 = distance(from: location, to: w1) ?? .infinity
                let d2 = distance(from: location, to: w2) ?? .infinity
                return d1 < d2
            }
        
        guard let closest = sortedWarnings.first,
              closest.id != lastAnnouncedWarningId,
              let dist = distance(from: location, to: closest) else {
            return
        }
        
        // Announce at specific distances
        if shouldAnnounce(distance: dist) {
            lastAnnouncedWarningId = closest.id
            
            // Voice announcement
            if voiceEnabled {
                let distanceText = dist < 1609 ? "\(Int(dist)) meters" : "\(String(format: "%.1f", dist / 1609.34)) miles"
                voiceAnnouncer.announce("\(closest.message) in \(distanceText)")
            }
            
            // Haptic feedback
            if hapticEnabled {
                if dist < 500 {
                    hapticFeedback.warning()
                } else {
                    hapticFeedback.notification()
                }
            }
        }
    }
    
    private func shouldAnnounce(distance: Double) -> Bool {
        // Announce at 3km, 1km, 500m
        return (distance <= 3000 && distance > 2900) ||
               (distance <= 1000 && distance > 900) ||
               (distance <= 500 && distance > 450)
    }
    
    // MARK: - Helpers
    
    private func distance(from location: CLLocation, to warning: TruckRestrictionWarning) -> Double? {
        guard let coord = warning.coordinate else { return nil }
        let warningLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return location.distance(from: warningLocation)
    }
    
    private func colorForWarningType(_ type: TruckRestrictionWarning.WarningType) -> Color {
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
    
    private func calculateRouteProgress() -> Double? {
        guard let route = currentRoute,
              let location = locationManager.currentLocation else {
            return nil
        }
        
        // Find closest point on route
        var minDistance = Double.infinity
        var closestIndex = 0
        
        for (index, coord) in route.coordinates.enumerated() {
            let dist = location.coordinate.distance(to: coord)
            if dist < minDistance {
                minDistance = dist
                closestIndex = index
            }
        }
        
        return Double(closestIndex) / Double(route.coordinates.count)
    }
}

// MARK: - Supporting Types

import Combine

extension TruckNavigationMapView {
    class ObservableWarningManager: ObservableObject {
        @Published var activeWarnings: [TruckRestrictionWarning] = []
    }
}

// MARK: - Route Details Sheet

struct RouteDetailsSheet: View {
    let route: TruckRoute
    let truckProfile: TruckProfile
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Route Information") {
                    LabeledContent("Distance", value: String(format: "%.1f miles", route.distanceMiles))
                    LabeledContent("Duration", value: String(format: "%.1f hours", route.durationHours))
                    LabeledContent("Destination", value: route.destinationName)
                }
                
                Section("Truck Profile") {
                    LabeledContent("Type", value: String(describing: truckProfile.truckType))
                    LabeledContent("Height", value: String(format: "%.1f ft", truckProfile.heightMeters * 3.28084))
                    LabeledContent("Weight", value: String(format: "%.0f lbs", truckProfile.weightTonnes * 2204.62))
                    LabeledContent("Length", value: String(format: "%.0f ft", truckProfile.lengthMeters * 3.28084))
                }
                
                if !route.truckNotices.isEmpty {
                    Section("Truck Restrictions (\(route.truckNotices.count))") {
                        ForEach(route.truckNotices, id: \.code) { notice in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(notice.title)
                                    .font(.subheadline)
                                if let details = notice.details {
                                    Text(details)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Section("Turn-by-Turn Directions (\(route.steps.count))") {
                    ForEach(Array(route.steps.enumerated()), id: \.offset) { index, step in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(index + 1). \(step.instruction)")
                                .font(.subheadline)
                            Text(String(format: "%.1f miles", step.distanceMeters / 1609.34))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Route Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    TruckNavigationMapView(
        truckProfile: .semiFiftyThree,
        destination: .constant(CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)),
        destinationName: .constant("Los Angeles, CA")
    )
}
