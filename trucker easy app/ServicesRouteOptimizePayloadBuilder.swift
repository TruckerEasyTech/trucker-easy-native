//
//  ServicesRouteOptimizePayloadBuilder.swift
//  trucker easy app
//
//  Monta o POST /v1/optimize a partir da carga ativa: GPS, geocode da origem, destino,
//  janelas de tempo (pickup/delivery), capacidade do camião (lbs) e correlação com Trip SwiftData.

import CoreLocation
import Foundation
import MapKit

struct RouteOptimizeBuiltPayload: Sendable {
    let request: RouteOptimizeRequestDTO
    /// id da paragem → coordenada e endereço legível (para aplicar a sequência no motor de geometria do app).
    let waypointLookup: [String: (coordinate: CLLocationCoordinate2D, address: String)]
}

enum RouteOptimizePayloadBuilderError: Error, LocalizedError {
    case missingCurrentLocation
    case geocodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingCurrentLocation:
            return "Current GPS location is required to optimize this route."
        case let .geocodeFailed(addr):
            return "Could not locate origin on map: \(addr)"
        }
    }
}

enum RouteOptimizePayloadBuilder {

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func isoString(from date: Date?) -> String? {
        guard let date else { return nil }
        return iso8601.string(from: date)
    }

    /// Geocode textual address (best effort near `hint`).
    static func geocodeAddress(_ address: String, near hint: CLLocationCoordinate2D?) async throws -> CLLocationCoordinate2D {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RouteOptimizePayloadBuilderError.geocodeFailed(address) }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = trimmed
        req.resultTypes = [.address, .pointOfInterest]
        if let hint {
            req.region = MKCoordinateRegion(
                center: hint,
                span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
            )
        }
        let response = try await MKLocalSearch(request: req).start()
        guard let item = response.mapItems.first else {
            throw RouteOptimizePayloadBuilderError.geocodeFailed(address)
        }
        return item.placemark.coordinate
    }

    /// Capacidade em **libras** (GVW aproximado a partir do perfil do veículo).
    static func vehicleCapacityLbs(truckProfile: TruckProfile) -> Double {
        truckProfile.weightTonnes * 2204.6226218
    }

    @MainActor
    static func build(
        load: DispatchedLoad,
        trip: Trip?,
        truckProfile: TruckProfile,
        currentLocation: CLLocation?,
        loadPickedUp: Bool
    ) async throws -> RouteOptimizeBuiltPayload {
        guard let here = currentLocation else { throw RouteOptimizePayloadBuilderError.missingCurrentLocation }
        let hint = here.coordinate
        let cap = vehicleCapacityLbs(truckProfile: truckProfile)
        let demand = load.weightLbs ?? 0

        var locations: [RouteOptimizeLocationDTO] = []
        var lookup: [String: (coordinate: CLLocationCoordinate2D, address: String)] = [:]

        let depotId = "depot"
        locations.append(
            RouteOptimizeLocationDTO(
                id: depotId,
                lat: hint.latitude,
                lng: hint.longitude,
                demand: 0,
                timeWindowStart: nil,
                timeWindowEnd: nil
            )
        )
        lookup[depotId] = (coordinate: hint, address: "Current location")

        if loadPickedUp {
            let destId = "delivery"
            locations.append(
                RouteOptimizeLocationDTO(
                    id: destId,
                    lat: load.destinationLatitude,
                    lng: load.destinationLongitude,
                    demand: max(0, demand),
                    timeWindowStart: nil,
                    timeWindowEnd: isoString(from: load.deliveryTime)
                )
            )
            lookup[destId] = (coordinate: load.destinationCoordinate, address: load.destinationAddress)
        } else {
            let pickupCoord: CLLocationCoordinate2D
            if load.originAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || load.originAddress == "Current Location" {
                pickupCoord = hint
            } else {
                pickupCoord = try await geocodeAddress(load.originAddress, near: hint)
            }
            let pickupId = "pickup"
            locations.append(
                RouteOptimizeLocationDTO(
                    id: pickupId,
                    lat: pickupCoord.latitude,
                    lng: pickupCoord.longitude,
                    demand: 0,
                    timeWindowStart: nil,
                    timeWindowEnd: isoString(from: load.pickupTime)
                )
            )
            lookup[pickupId] = (coordinate: pickupCoord, address: load.originAddress)

            let destId = "delivery"
            locations.append(
                RouteOptimizeLocationDTO(
                    id: destId,
                    lat: load.destinationLatitude,
                    lng: load.destinationLongitude,
                    demand: max(0, demand),
                    timeWindowStart: nil,
                    timeWindowEnd: isoString(from: load.deliveryTime)
                )
            )
            lookup[destId] = (coordinate: load.destinationCoordinate, address: load.destinationAddress)
        }

        let tripUUID = trip?.id.uuidString ?? "no-trip"
        let requestId = "TE-\(tripUUID)|L=\(load.id)|\(Int(Date().timeIntervalSince1970))"

        let dto = RouteOptimizeRequestDTO(
            requestId: requestId,
            fleetId: load.companyId ?? load.companyName ?? "",
            vehicleCapacity: cap,
            locations: locations,
            solverType: "hybrid_cqm",
            numVehicles: 1,
            tripId: trip?.id.uuidString,
            loadId: load.id
        )
        return RouteOptimizeBuiltPayload(request: dto, waypointLookup: lookup)
    }
}
