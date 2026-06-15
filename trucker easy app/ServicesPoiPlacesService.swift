import Foundation
import CoreLocation

// MARK: - Supabase poi_places / places_near RPC

struct PlacesNearRow: Decodable, Sendable {
    let id: UUID
    let osm_type: String?
    let osm_id: Int64?
    let poi_type: String
    let name: String?
    let brand: String?
    let operator_name: String?
    let network: String?
    let lat: Double
    let lon: Double
    let country_code: String?
    let has_shower: Bool
    let has_hgv_fuel: Bool
    let has_weigh_station: Bool
    let distance_m: Double?
    let diesel_price_usd: Double?
    let diesel_scraped_at: String?
    let rating: Double?
    let review_count: Int?
    let parking_status: String?
    let parking_available: Int?
    let parking_total: Int?
    let parking_reported_at: String?
    let restaurant_names: [String]?
    let has_healthy_options: Bool?
    let gov_weigh_status: String?
    let gov_weigh_source: String?
    let gov_weigh_updated_at: String?
    let gov_site_open: Bool?
    let gov_parking_available: Int?
    let gov_parking_total: Int?
    let poi_source: String?

    enum CodingKeys: String, CodingKey {
        case id, osm_type, osm_id, poi_type, name, brand, network, lat, lon, country_code
        case has_shower, has_hgv_fuel, has_weigh_station, distance_m, diesel_price_usd, diesel_scraped_at
        case rating, review_count, parking_status, parking_available, parking_total, parking_reported_at
        case restaurant_names, has_healthy_options
        case gov_weigh_status, gov_weigh_source, gov_weigh_updated_at, gov_site_open
        case gov_parking_available, gov_parking_total, poi_source
        case operator_name = "operator"
    }
}

enum PoiPlacesDataSource: String, Sendable {
    case supabase
    case mapKit
}

@MainActor
final class PoiPlacesService {
    static let shared = PoiPlacesService()

    private init() {}

    /// Truck-relevant POI types for driver map / Route Easy fuel hints.
    static let defaultPoiTypes = ["truck_stop", "fuel", "services", "shower", "weigh_station", "rest_area"]

    /// Official + OSM weigh stations ahead of the driver (Supabase `places_near`).
    func fetchWeighStationsNear(
        location: CLLocation,
        radiusMeters: Double = 20_000,
        limit: Int = 40
    ) async throws -> [PlacesNearRow] {
        try await fetchPlacesNear(
            location: location,
            radiusMeters: radiusMeters,
            poiTypes: ["weigh_station"],
            limit: limit
        )
    }

    func fetchPlacesNear(
        location: CLLocation,
        radiusMeters: Double = 24_000,   // 80km estourava o timeout de 15s; raio menor = query no limite
        poiTypes: [String]? = nil,
        limit: Int = 50
    ) async throws -> [PlacesNearRow] {
        let params = PlacesNearParams(
            p_lat: location.coordinate.latitude,
            p_lon: location.coordinate.longitude,
            p_radius_m: radiusMeters,
            p_poi_types: poiTypes ?? Self.defaultPoiTypes,
            p_limit: limit
        )
        return try await SupabaseClient.shared.rpc("places_near", params: params, responseType: PlacesNearRow.self)
    }
}

private struct PlacesNearParams: Encodable {
    let p_lat: Double
    let p_lon: Double
    let p_radius_m: Double
    let p_poi_types: [String]
    let p_limit: Int
}
