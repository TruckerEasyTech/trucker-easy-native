//
//  ModelsRouteOptimization.swift
//  trucker easy app
//
//  Contrato JSON com o middleware Python (POST /v1/optimize). O iOS não modela quântica — só DTOs.

import Foundation

struct RouteOptimizeLocationDTO: Codable, Sendable {
    let id: String
    let lat: Double
    let lng: Double
    var demand: Double
    var timeWindowStart: String?
    var timeWindowEnd: String?

    init(
        id: String,
        lat: Double,
        lng: Double,
        demand: Double = 0,
        timeWindowStart: String? = nil,
        timeWindowEnd: String? = nil
    ) {
        self.id = id
        self.lat = lat
        self.lng = lng
        self.demand = demand
        self.timeWindowStart = timeWindowStart
        self.timeWindowEnd = timeWindowEnd
    }

    private enum CodingKeys: String, CodingKey {
        case id, lat, lng, demand
        case timeWindowStart = "time_window_start"
        case timeWindowEnd = "time_window_end"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        lat = try c.decode(Double.self, forKey: .lat)
        lng = try c.decode(Double.self, forKey: .lng)
        demand = try c.decodeIfPresent(Double.self, forKey: .demand) ?? 0
        timeWindowStart = try c.decodeIfPresent(String.self, forKey: .timeWindowStart)
        timeWindowEnd = try c.decodeIfPresent(String.self, forKey: .timeWindowEnd)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(lat, forKey: .lat)
        try c.encode(lng, forKey: .lng)
        try c.encode(demand, forKey: .demand)
        try c.encodeIfPresent(timeWindowStart, forKey: .timeWindowStart)
        try c.encodeIfPresent(timeWindowEnd, forKey: .timeWindowEnd)
    }
}

struct RouteOptimizeRequestDTO: Codable, Sendable {
    let requestId: String
    let fleetId: String
    let vehicleCapacity: Double
    let locations: [RouteOptimizeLocationDTO]
    let solverType: String
    let numVehicles: Int
    /// UUID SwiftData `Trip` (auditoria / métricas).
    let tripId: String?
    let loadId: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case fleetId = "fleet_id"
        case vehicleCapacity = "vehicle_capacity"
        case locations
        case solverType = "solver_type"
        case numVehicles = "num_vehicles"
        case tripId = "trip_id"
        case loadId = "load_id"
    }

    init(
        requestId: String,
        fleetId: String,
        vehicleCapacity: Double,
        locations: [RouteOptimizeLocationDTO],
        solverType: String = "hybrid_cqm",
        numVehicles: Int = 1,
        tripId: String? = nil,
        loadId: String? = nil
    ) {
        self.requestId = requestId
        self.fleetId = fleetId
        self.vehicleCapacity = vehicleCapacity
        self.locations = locations
        self.solverType = solverType
        self.numVehicles = numVehicles
        self.tripId = tripId
        self.loadId = loadId
    }
}

/// Métricas de campo: poupança **aproximada** (percurso fechado Haversine) vs ordem manual no JSON.
struct RouteOptimizationMetricsDTO: Decodable, Sendable {
    let approxKmBaselineManualOrder: Double
    let approxKmOptimizedOrder: Double
    let approxKmSaved: Double
    let methodology: String?

    enum CodingKeys: String, CodingKey {
        case approxKmBaselineManualOrder = "approx_km_baseline_manual_order"
        case approxKmOptimizedOrder = "approx_km_optimized_order"
        case approxKmSaved = "approx_km_saved"
        case methodology
    }
}

struct RouteOptimizeResponseDTO: Decodable, Sendable {
    let requestId: String
    let status: String
    let solverUsed: String
    let orderedLocationIds: [String]
    let routes: [[String]]
    let message: String?
    let tripId: String?
    let loadId: String?
    let metrics: RouteOptimizationMetricsDTO?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case status
        case solverUsed = "solver_used"
        case orderedLocationIds = "ordered_location_ids"
        case routes
        case message
        case tripId = "trip_id"
        case loadId = "load_id"
        case metrics
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try c.decode(String.self, forKey: .requestId)
        status = try c.decode(String.self, forKey: .status)
        solverUsed = try c.decode(String.self, forKey: .solverUsed)
        orderedLocationIds = try c.decodeIfPresent([String].self, forKey: .orderedLocationIds) ?? []
        routes = try c.decodeIfPresent([[String]].self, forKey: .routes) ?? []
        message = try c.decodeIfPresent(String.self, forKey: .message)
        tripId = try c.decodeIfPresent(String.self, forKey: .tripId)
        loadId = try c.decodeIfPresent(String.self, forKey: .loadId)
        metrics = try c.decodeIfPresent(RouteOptimizationMetricsDTO.self, forKey: .metrics)
    }
}
