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
    let id: String
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
    
    // Inicializador direto.
    // `stableKey` sobrepõe a identidade derivada para warnings cuja `coordinate` é a posição
    // AO VIVO do caminhão (violações de compliance) — sem ele o id mudaria a cada fix de GPS e o
    // "fechar" (X) nunca grudaria. Notices fixos na rota omitem `stableKey` e usam (type|message|≈coord).
    init(type: WarningType, message: String, coordinate: CLLocationCoordinate2D?, stableKey: String? = nil) {
        self.type = type
        self.message = message
        self.coordinate = coordinate
        self.id = stableKey ?? Self.makeStableID(type: type, message: message, coordinate: coordinate)
    }

    private static func makeStableID(type: WarningType, message: String, coordinate: CLLocationCoordinate2D?) -> String {
        guard let c = coordinate else { return "\(type.rawValue)|\(message)" }
        // Bucket de ~111 m: uma restrição fixa mantém o mesmo id entre re-avaliações, enquanto duas
        // restrições distintas do mesmo tipo continuam separadas (segurança: nunca fundir 2 pontes).
        let lat = (c.latitude * 1000).rounded() / 1000
        let lon = (c.longitude * 1000).rounded() / 1000
        return "\(type.rawValue)|\(message)|\(lat)|\(lon)"
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
    @Binding var dismissedWarningIds: Set<String>
    
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
    var dismissedWarningIds: Set<String> = []
    
    private let warningDistance: Double = 5000
    private let regulationRefreshInterval: TimeInterval = 300
    private let regulationRefreshDistanceMeters: Double = 20_000
    private var lastAnnouncedId: String?
    private var currentRoute: TruckRoute?
    private var currentSpecs: TruckSpecifications?
    private var currentRegulations: RegulationProfile = .generic
    private var lastRegulationRefreshDate: Date = .distantPast
    private var lastRegulationRefreshCoordinate: CLLocationCoordinate2D?
    
    /// Voice announcement manager — shared with navigation layer
    let voiceManager = VoiceAnnouncementManager()
    
    /// Last geocoded ISO-3166-1 alpha-2 country code; avoids redundant reverse-geocoding calls
    private var lastDetectedISOCode: String?

    /// Limits expensive `RouteWarningEngine.evaluate` while driving — GPS updates can be very frequent.
    private var lastWarningEvalAt: Date = .distantPast
    private var lastWarningEvalLocation: CLLocation?

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
                let detected = await Self.reverseGeocodeISOCode(location: location)
                if let isoCode = detected {
                    self.currentRegulations = RegulationProfile.profile(forISOCode: isoCode)
                    self.lastDetectedISOCode = isoCode
                } else {
                    self.currentRegulations = .generic
                    self.lastDetectedISOCode = nil
                }
                self.lastRegulationRefreshDate = Date()
                self.lastRegulationRefreshCoordinate = startCoord
                #if DEBUG
                print("[Restrictions] 📍 Auto-detected regulations: \(currentRegulations.country.displayName(for: AppLanguage.persistedDriverChoice))")
                #endif
            }
        }
        
        // Generate smart warnings with engine
        let warnings = RouteWarningEngine.evaluate(
            route: route,
            userLocation: userLocation,
            specs: specs,
            regulations: currentRegulations,
            language: AppLanguage.persistedDriverChoice
        )
        
        // Mantém o que o motorista já fechou (X): reroute/reload da MESMA viagem não pode
        // ressuscitar warnings dispensados. O reset total fica só no clearWarnings (fim da viagem).
        self.activeWarnings = warnings.filter { !dismissedWarningIds.contains($0.id) }
        self.lastAnnouncedId = nil
        
        #if DEBUG
        print("[Restrictions] ✅ Loaded \(warnings.count) smart warnings from TruckRoute")
        #endif
    }
    
    // MARK: - Update Location (with smart re-evaluation)
    
    func updateLocation(_ location: CLLocation) {
        let now = Date()
        let dt = now.timeIntervalSince(lastWarningEvalAt)
        let moved = lastWarningEvalLocation.map { location.distance(from: $0) >= 40 } ?? true
        let shouldRunHeavyEval = dt >= 0.45 || moved

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

            if shouldRunHeavyEval {
                lastWarningEvalAt = now
                lastWarningEvalLocation = location
                let updatedWarnings = RouteWarningEngine.evaluate(
                    route: route,
                    userLocation: location,
                    specs: specs,
                    regulations: currentRegulations,
                    language: AppLanguage.persistedDriverChoice
                )

                // Preserve dismissed IDs + só REATRIBUI se mudou de verdade. Antes reatribuía a cada
                // ~0.45s mesmo idêntico → a overlay re-disparava a transição e o aviso "ficava subindo".
                let filtered = updatedWarnings.filter { !dismissedWarningIds.contains($0.id) }
                if filtered != self.activeWarnings {
                    self.activeWarnings = filtered
                }
            }
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
                #if DEBUG
                print("[Restrictions] 🔊 Voice triggered: \(closest.type.rawValue) at \(Int(distance))m")
                #endif
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
        let location = CLLocation(latitude: userLocation.coordinate.latitude,
                                  longitude: userLocation.coordinate.longitude)
        guard let isoCode = await Self.reverseGeocodeISOCode(location: location) else {
            lastRegulationRefreshDate = Date()
            lastRegulationRefreshCoordinate = userLocation.coordinate
            return
        }

        // Always record refresh so shouldRefreshRegulations backs off correctly
        lastRegulationRefreshDate = Date()
        lastRegulationRefreshCoordinate = userLocation.coordinate

        // ISO cache hit: skip profile lookup and warning re-evaluation
        guard isoCode != lastDetectedISOCode else {
            #if DEBUG
            print("[Restrictions] 📍 ISO unchanged (\(isoCode)) — skipping regulation refresh")
            #endif
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
            regulations: currentRegulations,
            language: AppLanguage.persistedDriverChoice
        )
        #if DEBUG
        print("[Restrictions] 🌍 Regulation profile updated: \(currentRegulations.country.displayName(for: AppLanguage.persistedDriverChoice))")
        #endif
    }

    /// Reverse geocode a location to ISO-3166-1 alpha-2 country code.
    /// Uses MKReverseGeocodingRequest on iOS 26+, CLGeocoder on earlier versions.
    private static func reverseGeocodeISOCode(location: CLLocation) async -> String? {
        // Offline: o reverse-geocode (CLGeocoder/MK) pendura ~30s até dar timeout. Curto-circuita
        // na hora — o chamador (loadWarnings) cai pro perfil de regulação base sem travar.
        guard await MainActor.run(body: { NetworkReachability.shared.isOnline }) else { return nil }
        if #available(iOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = try? await request.mapItems.first,
                  let code = item.addressRepresentations?.region?.identifier.uppercased() else {
                return nil
            }
            return code
        } else {
            do {
                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                return placemarks.first?.isoCountryCode?.uppercased()
            } catch {
                return nil
            }
        }
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

