import Foundation
import CoreLocation

/// Official trucking POI feed — Road511 (511/DOT/NBI aggregator) + NextBillion browse via Supabase Edge.
/// These are licensed / government-normalized feeds, not driver crowd reports.
@MainActor
final class TruckingPoiFeedService {
    static let shared = TruckingPoiFeedService()

    private(set) var lastSources: [String] = []
    private(set) var lastWeighSignals: [PartnerWeighSignal] = []
    private(set) var lastError: String?
    private var lastRefresh: Date = .distantPast
    private let refreshInterval: TimeInterval = 180

    private init() {}

    struct FeedResponse: Decodable {
        let sources: [String]?
        let weigh_signals: [PartnerWeighSignal]?
        let parking_signals: [PartnerParkingSignal]?
        let places: [TruckingPlaceFeedRow]?
    }

    struct TruckingPlaceFeedRow: Decodable, Sendable {
        let external_id: String
        let external_source: String
        let poi_type: String
        let name: String
        let lat: Double
        let lon: Double
        let has_shower: Bool?
        let amenities: [String]?
        let status_open: Bool?
        let parking_available: Int?
        let parking_total: Int?
    }

    func refreshIfNeeded(for coordinate: CLLocationCoordinate2D, persist: Bool = true) async {
        let now = Date()
        guard now.timeIntervalSince(lastRefresh) >= refreshInterval else { return }
        lastRefresh = now
        do {
            let response = try await fetch(lat: coordinate.latitude, lon: coordinate.longitude, persist: persist)
            lastSources = response.sources ?? []
            lastWeighSignals = response.weigh_signals ?? []
            lastError = nil
            applyToOperationalFeed(response)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func fetch(
        lat: Double,
        lon: Double,
        radiusKm: Double = 80,
        persist: Bool = false
    ) async throws -> FeedResponse {
        var components = URLComponents(string: "\(SupabaseConfig.projectURL)/functions/v1/trucking-poi-feed")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lon)),
            URLQueryItem(name: "radius_km", value: String(radiusKm)),
            URLQueryItem(name: "persist", value: persist ? "1" : "0"),
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = SupabaseClient.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FeedResponse.self, from: data)
    }

    /// Match Road511 / partner weigh signal within 500 m of a detected station.
    func officialWeighStatus(near coordinate: CLLocationCoordinate2D) -> WeighStationStatus? {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let match = lastWeighSignals
            .map { signal -> (PartnerWeighSignal, Double) in
                let loc = CLLocation(latitude: signal.latitude, longitude: signal.longitude)
                return (signal, here.distance(from: loc))
            }
            .filter { $0.1 <= 500 }
            .min(by: { $0.1 < $1.1 })?
            .0
        guard let match else { return nil }
        switch match.status.lowercased() {
        case "open": return .open
        case "closed": return .closed
        default: return .monitoring
        }
    }

    private func applyToOperationalFeed(_ feed: FeedResponse) {
        let ops = OperationalFeedService.shared
        if let weigh = feed.weigh_signals, !weigh.isEmpty {
            for signal in weigh {
                let status: WeighStationStatus
                switch signal.status.lowercased() {
                case "open": status = .open
                case "closed": status = .closed
                default: status = .monitoring
                }
                WeighStationStatusService.shared.setPartnerStatus(
                    status,
                    for: signal.stationName,
                    updatedAt: signal.updatedAt ?? Date()
                )
            }
        }
        if let parking = feed.parking_signals {
            ops.ingestPartnerParkingSignals(parking)
        }
    }
}
