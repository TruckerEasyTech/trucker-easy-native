//
//  TruckRestrictionAlertView.swift
//  trucker easy app
//
//  TRUCK RESTRICTION ALERTS - FIXED VERSION

import SwiftUI
import CoreLocation
import AVFoundation
import MapKit

// MARK: - Truck Restriction Warning Model
struct TruckRestrictionWarning: Identifiable, Equatable {
    let id = UUID()
    let type: WarningType
    let message: String
    var coordinate: CLLocationCoordinate2D?
    
    enum WarningType: String {
        case lowBridge = "Low Bridge"
        case heightLimit = "Height Limit"
        case weightLimit = "Weight Limit"
        case hazmat = "Hazmat"
        case tunnel = "Tunnel"
        case narrowRoad = "Narrow Road"
        case general = "Warning"
        
        var icon: String {
            switch self {
            case .lowBridge, .heightLimit:
                return "arrow.down.to.line.compact"
            case .weightLimit:
                return "scalemass.fill"
            case .hazmat:
                return "exclamationmark.triangle.fill"
            case .tunnel:
                return "mountain.2.fill"
            case .narrowRoad:
                return "road.lanes"
            case .general:
                return "exclamationmark.circle.fill"
            }
        }
    }
    
    // Inicializador direto
    init(type: WarningType, message: String, coordinate: CLLocationCoordinate2D?) {
        self.type = type
        self.message = message
        self.coordinate = coordinate
    }

    static func == (lhs: TruckRestrictionWarning, rhs: TruckRestrictionWarning) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Alert View
struct TruckRestrictionAlertView: View {
    let warning: TruckRestrictionWarning
    let distanceMeters: Double
    let onDismiss: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: warning.type.icon)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(colorForType(warning.type))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(colorForType(warning.type).opacity(0.15))
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(warning.type.rawValue.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(colorForType(warning.type))
                    
                    Text(warning.message)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(isExpanded ? nil : 2)
                    
                    Text(formatDistance(distanceMeters))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(colorForType(warning.type).opacity(0.3), lineWidth: 2)
                    )
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            }
            
            if isExpanded, let coord = warning.coordinate {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Location")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    
                    Text(String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(uiColor: .systemBackground).opacity(0.6))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .shadow(color: colorForType(warning.type).opacity(0.3), radius: 12, x: 0, y: 4)
    }
    
    private func colorForType(_ type: TruckRestrictionWarning.WarningType) -> Color {
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
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 100 {
            return "⚠️ AHEAD NOW"
        } else if meters < 500 {
            return "⚠️ \(Int(meters))m ahead"
        } else if meters < 1609 {
            return "⚠️ \(Int(meters))m ahead"
        } else {
            let miles = meters / 1609.34
            return "⚠️ \(String(format: "%.1f", miles)) miles ahead"
        }
    }
}

// MARK: - Restrictions Overlay
struct TruckRestrictionsOverlay: View {
    let warnings: [TruckRestrictionWarning]
    let currentLocation: CLLocation?
    @Binding var dismissedWarningIds: Set<UUID>
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(sortedWarnings) { warning in
                if !dismissedWarningIds.contains(warning.id),
                   let distance = distanceToWarning(warning) {
                    
                    TruckRestrictionAlertView(
                        warning: warning,
                        distanceMeters: distance,
                        onDismiss: {
                            withAnimation {
                                _ = dismissedWarningIds.insert(warning.id)
                            }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
            }
        }
        .padding(.horizontal)
    }
    
    private var sortedWarnings: [TruckRestrictionWarning] {
        warnings.sorted { w1, w2 in
            let d1 = distanceToWarning(w1) ?? Double.infinity
            let d2 = distanceToWarning(w2) ?? Double.infinity
            return d1 < d2
        }
    }
    
    private func distanceToWarning(_ warning: TruckRestrictionWarning) -> Double? {
        guard let current = currentLocation,
              let warningCoord = warning.coordinate else {
            return nil
        }
        
        let warningLocation = CLLocation(
            latitude: warningCoord.latitude,
            longitude: warningCoord.longitude
        )
        
        return current.distance(from: warningLocation)
    }
}

// MARK: - Warning Manager
@Observable
@MainActor
class TruckRestrictionWarningManager {
    var activeWarnings: [TruckRestrictionWarning] = []
    var dismissedWarningIds: Set<UUID> = []
    
    private let warningDistance: Double = 5000
    private let regulationRefreshInterval: TimeInterval = 300
    private let regulationRefreshDistanceMeters: Double = 20_000
    private var lastAnnouncedId: UUID?
    private var currentRoute: TruckRoute?
    private var currentSpecs: TruckSpecifications?
    private var currentRegulations: RegulationProfile = .generic
    private var lastRegulationRefreshDate: Date = .distantPast
    private var lastRegulationRefreshCoordinate: CLLocationCoordinate2D?
    
    /// Voice announcement manager — shared with navigation layer
    let voiceManager = VoiceAnnouncementManager()
    
    /// Last geocoded ISO-3166-1 alpha-2 country code; avoids redundant reverse-geocoding calls
    private var lastDetectedISOCode: String?
    
    // MARK: - Load Warnings from TruckRoute (with smart engine)
    
    /// Carrega warnings de um TruckRoute usando o RouteWarningEngine
    /// - Parameters:
    ///   - route: TruckRoute calculado
    ///   - userLocation: Localização atual do usuário
    ///   - specs: Especificações do caminhão
    ///   - regulations: Perfil de regulamentação (opcional, detecta automaticamente)
    func loadWarnings(
        from route: TruckRoute,
        userLocation: CLLocation,
        specs: TruckSpecifications,
        regulations: RegulationProfile? = nil
    ) async {
        // Store route and specs for location updates
        self.currentRoute = route
        self.currentSpecs = specs
        
        // Detect regulations if not provided
        if let regs = regulations {
            self.currentRegulations = regs
            self.lastDetectedISOCode = isoCodeForCountry(regs.country)
        } else {
            // Auto-detect from route start coordinate via reverse geocoding
            if let startCoord = route.coordinates.first {
                let location = CLLocation(latitude: startCoord.latitude, longitude: startCoord.longitude)
                if let request = MKReverseGeocodingRequest(location: location),
                   let item = try? await request.mapItems.first,
                   let isoCode = item.addressRepresentations?.region?.identifier.uppercased() {
                    self.currentRegulations = RegulationProfile.profile(forISOCode: isoCode)
                    self.lastDetectedISOCode = isoCode
                } else {
                    self.currentRegulations = .generic
                    self.lastDetectedISOCode = nil
                }
                self.lastRegulationRefreshDate = Date()
                self.lastRegulationRefreshCoordinate = startCoord
                print("[Restrictions] 📍 Auto-detected regulations: \(currentRegulations.country.displayName)")
            }
        }
        
        // Generate smart warnings with engine
        let warnings = RouteWarningEngine.evaluate(
            route: route,
            userLocation: userLocation,
            specs: specs,
            regulations: currentRegulations
        )
        
        self.activeWarnings = warnings
        self.dismissedWarningIds.removeAll()
        self.lastAnnouncedId = nil
        
        print("[Restrictions] ✅ Loaded \(warnings.count) smart warnings from TruckRoute")
    }
    
    // MARK: - Update Location (with smart re-evaluation)
    
    func updateLocation(_ location: CLLocation) {
        // Re-evaluate warnings if we have route and specs
        if let route = currentRoute, let specs = currentSpecs {
            if shouldRefreshRegulations(for: location.coordinate) {
                Task { @MainActor in
                    await refreshRegulationsAndWarningsIfNeeded(
                        route: route,
                        specs: specs,
                        userLocation: location
                    )
                }
            }

            let updatedWarnings = RouteWarningEngine.evaluate(
                route: route,
                userLocation: location,
                specs: specs,
                regulations: currentRegulations
            )
            
            // Preserve dismissed IDs
            self.activeWarnings = updatedWarnings
        }
        
        // Legacy behavior: filter by distance
        guard !activeWarnings.isEmpty else { return }
        
        let nearbyWarnings = activeWarnings.filter { warning in
            guard let coord = warning.coordinate else { return false }
            let warningLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let distance = location.distance(from: warningLocation)
            return distance < warningDistance && !dismissedWarningIds.contains(warning.id)
        }
        
        // Announce closest warning at specific intervals
        if let closest = nearbyWarnings.first,
           lastAnnouncedId != closest.id,
           let coord = closest.coordinate {
            
            let warningLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let distance = location.distance(from: warningLocation)
            
            if distance <= 3000 && distance > 2900 ||
               distance <= 1000 && distance > 900 ||
               distance <= 500 && distance > 450 {
                
                lastAnnouncedId = closest.id
                // Announce restriction via voice with smart deduplication
                voiceManager.announceWarning(closest, distance: distance)
                print("[Restrictions] 🔊 Voice triggered: \(closest.type.rawValue) at \(Int(distance))m")
            }
        }
    }
    
    func clearWarnings() {
        activeWarnings.removeAll()
        dismissedWarningIds.removeAll()
        lastAnnouncedId = nil
        currentRoute = nil
        currentSpecs = nil
        currentRegulations = .generic
        lastRegulationRefreshDate = .distantPast
        lastRegulationRefreshCoordinate = nil
        lastDetectedISOCode = nil
        voiceManager.resetDeduplication()
    }

    private func shouldRefreshRegulations(for coordinate: CLLocationCoordinate2D) -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastRegulationRefreshDate) >= regulationRefreshInterval else {
            return false
        }

        guard let lastCoordinate = lastRegulationRefreshCoordinate else {
            return true
        }
        let current = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let previous = CLLocation(latitude: lastCoordinate.latitude, longitude: lastCoordinate.longitude)
        return current.distance(from: previous) >= regulationRefreshDistanceMeters
    }

    private func refreshRegulationsAndWarningsIfNeeded(
        route: TruckRoute,
        specs: TruckSpecifications,
        userLocation: CLLocation
    ) async {
        // Geocode once to get the ISO country code (MKReverseGeocodingRequest — iOS 26+)
        let location = CLLocation(latitude: userLocation.coordinate.latitude,
                                  longitude: userLocation.coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first,
              let isoCode = item.addressRepresentations?.region?.identifier.uppercased() else {
            // Record attempt to avoid rapid retries even on failure
            lastRegulationRefreshDate = Date()
            lastRegulationRefreshCoordinate = userLocation.coordinate
            return
        }

        // Always record refresh so shouldRefreshRegulations backs off correctly
        lastRegulationRefreshDate = Date()
        lastRegulationRefreshCoordinate = userLocation.coordinate

        // ISO cache hit: skip profile lookup and warning re-evaluation
        guard isoCode != lastDetectedISOCode else {
            print("[Restrictions] 📍 ISO unchanged (\(isoCode)) — skipping regulation refresh")
            return
        }
        lastDetectedISOCode = isoCode

        let detectedRegulations = RegulationProfile.profile(forISOCode: isoCode)
        guard detectedRegulations.country != currentRegulations.country else { return }

        currentRegulations = detectedRegulations
        activeWarnings = RouteWarningEngine.evaluate(
            route: route,
            userLocation: userLocation,
            specs: specs,
            regulations: currentRegulations
        )
        print("[Restrictions] 🌍 Regulation profile updated: \(currentRegulations.country.displayName)")
    }

    /// Maps Country enum to ISO-3166-1 alpha-2 string for cache comparisons
    private func isoCodeForCountry(_ country: RegulationProfile.Country) -> String {
        switch country {
        case .usa:       return "US"
        case .canada:    return "CA"
        case .uk:        return "GB"
        case .germany:   return "DE"
        case .france:    return "FR"
        case .brazil:    return "BR"
        case .mexico:    return "MX"
        case .australia: return "AU"
        case .eu:        return "EU"
        case .generic:   return ""
        }
    }
}

