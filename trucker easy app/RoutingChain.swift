//
//  RoutingChain.swift
//  trucker easy app
//
//  Fachada tipada: Valhalla → OSRM → MapKit → cache (implementação em `RoutingService.calculateTruckRoute`).
//

import CoreLocation
import Foundation
import OSLog

typealias RouteResult = TruckRoute

struct RoutingChain {
    fileprivate let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TruckerEasy", category: "RoutingChain")
}

extension RoutingChain {
    @MainActor
    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> RouteResult {
        try await route(from: from, to: to, destinationName: "", profile: TruckProfile.loadSaved(), avoidTolls: false)
    }

    @MainActor
    func route(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        destinationName: String,
        profile: TruckProfile,
        avoidTolls: Bool = false
    ) async throws -> RouteResult {
        let origin = CLLocation(latitude: from.latitude, longitude: from.longitude)

        do {
            return try await RoutingService.shared.calculateTruckRoute(
                from: origin,
                to: to,
                destinationName: destinationName,
                profile: profile,
                avoidTolls: avoidTolls
            )
        } catch {
            logger.warning("RoutingChain: falha em todas as fontes — \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
