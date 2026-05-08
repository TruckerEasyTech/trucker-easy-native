// ServicesValhallaRoutingService.swift
// trucker easy app
//
// Valhalla open-source truck routing — self-hosted, zero per-user cost.
//
// INFRASTRUCTURE SETUP (one-time, ~$50/month fixed):
//   1. Spin up a server (DigitalOcean 8GB Droplet or AWS c5.large)
//   2. docker pull valhalla/valhalla:run-latest
//   3. Download OSM data: wget https://download.geofabrik.de/north-america/us-latest.osm.pbf
//   4. Build truck routing tiles:
//      docker run -v /data:/data valhalla/valhalla:run-latest \
//        valhalla_build_config --mjolnir-tile-dir /data/tiles > valhalla.json
//      docker run -v /data:/data valhalla/valhalla:run-latest \
//        valhalla_build_tiles -c valhalla.json /data/us-latest.osm.pbf
//   5. Run: docker run -d -p 8002:8002 -v /data:/data valhalla/valhalla:run-latest
//   6. Set Info.plist key "ValhallaServerURL" = "https://your-server.com"
//
// COST COMPARISON:
//   Commercial truck APIs: ~$10/driver/month  → 100 drivers = $1,000/month variable
//   Valhalla (own):    ~$50-100/month fixed → 1,000 drivers = $0.05-0.10/driver
//
// API DOCS: https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/

import Foundation
import CoreLocation
import MapKit

// MARK: - Valhalla Routing Service

@MainActor
@Observable
final class ValhallaRoutingService {
    static let shared = ValhallaRoutingService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private init() {}

    // Read the self-hosted Valhalla server URL from Info.plist.
    // Add key "ValhallaServerURL" with your server's base URL.
    var serverURL: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "ValhallaServerURL") as? String ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "||", with: "//")
    }

    /// Same source as the merged app Info.plist — fails closed if xcconfig did not substitute `$(VALHALLA_SERVER_URL)`.
    var isAvailable: Bool {
        guard let url = Bundle.main.infoDictionary?["ValhallaServerURL"] as? String,
              !url.isEmpty,
              !url.contains("$(") else {
            return false
        }
        return true
    }

    // MARK: - Calculate Truck Route

    /// Calls your self-hosted Valhalla server and returns a TruckRoute (app's internal model).
    /// Valhalla "truck" costing respects height, weight, length, axle limits, and hazmat.
    func calculateTruckRoute(
        from origin: CLLocation,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        profile: TruckProfile,
        avoidTolls: Bool = false
    ) async throws -> TruckRoute {
        guard isAvailable else {
            throw ValhallaError.serverNotConfigured
        }

        let url = URL(string: "\(serverURL)/route")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try buildRequestBody(
            from: origin.coordinate,
            to: destination,
            profile: profile,
            avoidTolls: avoidTolls
        )

        print("[Valhalla] Requesting truck route to \(destinationName)...")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ValhallaError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "empty"
            print("[Valhalla] HTTP \(http.statusCode): \(body)")
            throw ValhallaError.serverError(http.statusCode)
        }

        let valhalla = try JSONDecoder().decode(ValhallaRouteResponse.self, from: data)
        let route = try parseRoute(valhalla, destinationName: destinationName)
        print("[Valhalla] Route: \(String(format: "%.1f", route.distanceMiles)) mi, \(Int(route.durationSeconds / 60)) min, \(route.steps.count) steps")
        return route
    }

    // MARK: - Build Request Body

    private func buildRequestBody(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        profile: TruckProfile,
        avoidTolls: Bool
    ) throws -> Data {
        // Valhalla truck costing options — maps directly to TruckProfile dimensions
        var costingOptions: [String: Any] = [
            "height": profile.heightMeters,             // meters
            "width":  2.59,                             // standard semi width 8.5ft (TruckProfile has no width field)
            "length": profile.lengthMeters,             // meters
            "weight": profile.weightTonnes * 0.907185,  // short tons → metric tonnes
            "axle_load": profile.axleWeightTonnes * 0.907185  // short tons → metric tonnes per axle
        ]

        if avoidTolls {
            costingOptions["toll_booth_penalty"] = 9999
        }

        // Hazmat flag — if truck carries hazmat, Valhalla routes around restrictions
        if profile.hasHazmat {
            costingOptions["hazmat"] = true
        }

        let body: [String: Any] = [
            "locations": [
                ["lon": origin.longitude, "lat": origin.latitude, "type": "break"],
                ["lon": destination.longitude, "lat": destination.latitude, "type": "break"]
            ],
            "costing": "truck",
            "costing_options": ["truck": costingOptions],
            "directions_options": [
                "units": "miles",
                "language": "en-US"
            ],
            "shape_match": "walk_or_snap"
        ]

        return try JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Parse Valhalla Response → TruckRoute

    private func parseRoute(_ response: ValhallaRouteResponse, destinationName: String) throws -> TruckRoute {
        let trip = response.trip

        guard !trip.legs.isEmpty else { throw ValhallaError.noRoute }

        // Decode all coordinates from all legs (Valhalla encodes each leg's shape as polyline6)
        var allCoordinates: [CLLocationCoordinate2D] = []
        var allSteps: [RouteStep] = []

        for leg in trip.legs {
            let coords = StandardPolylineDecoder.decode(leg.shape, precision: 6)
            allCoordinates.append(contentsOf: coords)

            for maneuver in leg.maneuvers {
                // Skip trivial "depart" / "arrive" with no instruction content
                let instruction = maneuver.instruction.trimmingCharacters(in: .whitespaces)
                guard !instruction.isEmpty else { continue }

                allSteps.append(RouteStep(
                    instruction: instruction,
                    distanceMeters: maneuver.length * 1609.34,    // miles → meters
                    durationSeconds: Double(maneuver.time),
                    maneuver: ValhallaManeuverType(rawValue: maneuver.type)?.instruction ?? instruction
                ))
            }
        }

        guard !allCoordinates.isEmpty else { throw ValhallaError.emptyPolyline }

        let totalDistanceMeters = Double(trip.summary.length) * 1609.34   // miles → meters
        let totalDurationSeconds = Double(trip.summary.time)

        return TruckRoute(
            coordinates: allCoordinates,
            steps: allSteps,
            distanceMeters: totalDistanceMeters,
            durationSeconds: totalDurationSeconds,
            destinationName: destinationName,
            truckNotices: extractNotices(from: trip)
        )
    }

    // MARK: - Extract Truck Restriction Notices

    private func extractNotices(from trip: ValhallaTrip) -> [TruckRouteNotice] {
        var notices: [TruckRouteNotice] = []
        for leg in trip.legs {
            for maneuver in leg.maneuvers {
                // Valhalla flags restricted maneuvers with has_time_restrictions or similar
                if maneuver.hasTimeRestrictions == true {
                    notices.append(TruckRouteNotice(
                        code: "time_restriction",
                        title: "Time-restricted road segment ahead",
                        details: maneuver.instruction
                    ))
                }
            }
        }
        return notices
    }
}

// MARK: - Valhalla Errors

enum ValhallaError: LocalizedError {
    case serverNotConfigured
    case invalidResponse
    case serverError(Int)
    case noRoute
    case emptyPolyline

    var errorDescription: String? {
        switch self {
        case .serverNotConfigured:
            return "Valhalla server URL not set in Info.plist (key: ValhallaServerURL)"
        case .invalidResponse:
            return "Invalid response from Valhalla server"
        case .serverError(let code):
            return "Valhalla server error \(code)"
        case .noRoute:
            return "Valhalla found no route"
        case .emptyPolyline:
            return "Valhalla returned empty polyline"
        }
    }
}

// MARK: - Valhalla Response Models

private struct ValhallaRouteResponse: Decodable {
    let trip: ValhallaTrip
}

private struct ValhallaTrip: Decodable {
    let summary: ValhallaSummary
    let legs: [ValhallaLeg]
}

private struct ValhallaSummary: Decodable {
    let length: Double      // miles (we asked for "units": "miles")
    let time: Int           // seconds
}

private struct ValhallaLeg: Decodable {
    let shape: String                   // polyline6-encoded coordinates
    let maneuvers: [ValhallaManeuver]
}

private struct ValhallaManeuver: Decodable {
    let type: Int
    let instruction: String
    let length: Double                  // miles
    let time: Int                       // seconds
    let hasTimeRestrictions: Bool?

    enum CodingKeys: String, CodingKey {
        case type, instruction, length, time
        case hasTimeRestrictions = "has_time_restrictions"
    }
}

// MARK: - Valhalla Maneuver Types → Human-Readable Direction

private enum ValhallaManeuverType: Int {
    case none = 0
    case start = 1
    case startRight = 2
    case startLeft = 3
    case destination = 4
    case destinationRight = 5
    case destinationLeft = 6
    case becomes = 7
    case continueAhead = 8
    case slightRight = 9
    case right = 10
    case sharpRight = 11
    case uturnRight = 12
    case uturnLeft = 13
    case sharpLeft = 14
    case left = 15
    case slightLeft = 16
    case rampStraight = 17
    case rampRight = 18
    case rampLeft = 19
    case exitRight = 20
    case exitLeft = 21
    case stayStraight = 22
    case stayRight = 23
    case stayLeft = 24
    case merge = 25
    case roundaboutEnter = 26
    case roundaboutExit = 27
    case ferryEnter = 28
    case ferryExit = 29

    /// Direction word for voice/display — used as `maneuver` field in RouteStep
    var instruction: String {
        switch self {
        case .none, .start, .startRight, .startLeft: return "Depart"
        case .destination, .destinationRight, .destinationLeft: return "Arrive at destination"
        case .becomes: return "Continue"
        case .continueAhead: return "Continue straight"
        case .slightRight: return "Bear right"
        case .right: return "Turn right"
        case .sharpRight: return "Turn sharply right"
        case .uturnRight, .uturnLeft: return "Make a U-turn"
        case .sharpLeft: return "Turn sharply left"
        case .left: return "Turn left"
        case .slightLeft: return "Bear left"
        case .rampStraight: return "Take the ramp straight"
        case .rampRight: return "Take the ramp on the right"
        case .rampLeft: return "Take the ramp on the left"
        case .exitRight: return "Take the exit on the right"
        case .exitLeft: return "Take the exit on the left"
        case .stayStraight: return "Stay straight"
        case .stayRight: return "Stay right"
        case .stayLeft: return "Stay left"
        case .merge: return "Merge"
        case .roundaboutEnter: return "Enter roundabout"
        case .roundaboutExit: return "Exit roundabout"
        case .ferryEnter: return "Take the ferry"
        case .ferryExit: return "Leave the ferry"
        }
    }
}

