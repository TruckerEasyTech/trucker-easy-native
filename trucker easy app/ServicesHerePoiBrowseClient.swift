import Foundation
import CoreLocation

/// Optional HERE Geocoding & Search browse — same category system Trucker Path / commercial nav apps license.
/// Categories: 700-7900-0131 truck parking, 4200 fuel, etc. Requires HERE_API_KEY (commercial).
/// App works without this; OSM + NTAD + crowd are the free baseline.
enum HerePoiBrowseClient {
    private static var apiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "HERE_API_KEY") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var isConfigured: Bool { !apiKey.isEmpty }

    /// Truck parking + fuel + rest areas near a point (250 km max per HERE browse API).
    static func fetchTruckPlaces(
        near location: CLLocation,
        limit: Int = 30
    ) async throws -> [HereBrowsePlace] {
        guard isConfigured else { return [] }
        let at = String(format: "%.5f,%.5f", location.coordinate.latitude, location.coordinate.longitude)
        let categories = "700-7900-0131,4200,800-8500-0131"
        var components = URLComponents(string: "https://browse.search.hereapi.com/v1/browse")!
        components.queryItems = [
            URLQueryItem(name: "at", value: at),
            URLQueryItem(name: "categories", value: categories),
            URLQueryItem(name: "limit", value: String(min(limit, 100))),
            URLQueryItem(name: "apiKey", value: apiKey),
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }
        let decoded = try JSONDecoder().decode(HereBrowseResponse.self, from: data)
        return decoded.items ?? []
    }
}

struct HereBrowsePlace: Decodable, Sendable {
    let id: String?
    let title: String?
    let address: HereBrowseAddress?
    let position: HereBrowsePosition?
    let categories: [HereBrowseCategory]?
}

struct HereBrowseAddress: Decodable, Sendable {
    let label: String?
}

struct HereBrowsePosition: Decodable, Sendable {
    let lat: Double
    let lng: Double
}

struct HereBrowseCategory: Decodable, Sendable {
    let id: String?
    let name: String?
}

private struct HereBrowseResponse: Decodable {
    let items: [HereBrowsePlace]?
}
