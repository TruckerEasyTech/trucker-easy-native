import Foundation
import CoreLocation
import Observation

private enum OperationalFeedConfig {
    static var baseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "OperationalFeedAPIBaseURL") as? String ?? ""
    }

    static var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "OperationalFeedAPIKey") as? String ?? ""
    }

    static var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !providerURLs.isEmpty
    }

    static var providerURLs: [String] {
        let raw = Bundle.main.object(forInfoDictionaryKey: "OperationalFeedProviderURLs") as? String ?? ""
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct PartnerParkingSignal: Decodable {
    let locationName: String
    let latitude: Double
    let longitude: Double
    let availableSlots: Int?
    let totalSlots: Int?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case locationName = "location_name"
        case latitude
        case longitude
        case availableSlots = "available_slots"
        case totalSlots = "total_slots"
        case updatedAt = "updated_at"
    }
}

struct PartnerWeighSignal: Decodable {
    let stationName: String
    let latitude: Double
    let longitude: Double
    let status: String
    let updatedAt: Date?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case stationName = "station_name"
        case latitude
        case longitude
        case status
        case updatedAt = "updated_at"
        case source
    }
}

private struct PartnerOperationalFeedResponse: Decodable {
    let parkingSignals: [PartnerParkingSignal]
    let weighSignals: [PartnerWeighSignal]

    init(parkingSignals: [PartnerParkingSignal], weighSignals: [PartnerWeighSignal]) {
        self.parkingSignals = parkingSignals
        self.weighSignals = weighSignals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        parkingSignals = try container.decodeIfPresent([PartnerParkingSignal].self, forKey: .parkingSignals) ?? []
        weighSignals = try container.decodeIfPresent([PartnerWeighSignal].self, forKey: .weighSignals) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case parkingSignals = "parking_signals"
        case weighSignals = "weigh_signals"
    }
}

@MainActor
@Observable
final class OperationalFeedService {
    static let shared = OperationalFeedService()

    private(set) var parkingSignals: [PartnerParkingSignal] = []
    private(set) var weighSignals: [PartnerWeighSignal] = []
    private(set) var lastError: String?
    private(set) var lastSuccessfulSource: String?
    private(set) var lastSuccessfulAt: Date?
    private(set) var sourceHealth: [String: String] = [:]

    private var lastRefresh: Date = .distantPast
    private let refreshInterval: TimeInterval = 180

    private init() {}

    func refreshIfNeeded(for coordinate: CLLocationCoordinate2D) async {
        let now = Date()
        guard now.timeIntervalSince(lastRefresh) >= refreshInterval else { return }
        lastRefresh = now

        do {
            let responses = try await fetchAll(lat: coordinate.latitude, lon: coordinate.longitude)
            parkingSignals = mergeParkingSignals(from: responses.map { $0.response.parkingSignals })
            weighSignals = mergeWeighSignals(from: responses.map { $0.response.weighSignals })
            lastError = nil
            lastSuccessfulAt = now
            lastSuccessfulSource = responses.map { $0.source }.joined(separator: " + ")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func applyWeighSignals() {
        let service = WeighStationStatusService.shared
        for signal in weighSignals {
            let status: WeighStationStatus
            switch signal.status.lowercased() {
            case "open": status = .open
            case "closed": status = .closed
            default: status = .monitoring
            }
            service.setPartnerStatus(
                status,
                for: signal.stationName,
                updatedAt: signal.updatedAt ?? Date(),
                source: signal.source
            )
        }
    }

    func ingestPartnerParkingSignals(_ incoming: [PartnerParkingSignal]) {
        parkingSignals = mergeParkingSignals(from: [incoming, parkingSignals])
    }

    private func fetchAll(lat: Double, lon: Double) async throws -> [(source: String, response: PartnerOperationalFeedResponse)] {
        var results: [(String, PartnerOperationalFeedResponse)] = []
        var newHealth: [String: String] = [:]

        for url in OperationalFeedConfig.providerURLs {
            do {
                let response = try await fetchFromConfiguredProvider(baseURL: url, lat: lat, lon: lon)
                results.append(("official:\(url)", response))
                newHealth["official:\(url)"] = "ok"
            } catch {
                newHealth["official:\(url)"] = "error: \(error.localizedDescription)"
            }
        }

        if OperationalFeedConfig.providerURLs.isEmpty, !OperationalFeedConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let response = try await fetchFromConfiguredProvider(baseURL: OperationalFeedConfig.baseURL, lat: lat, lon: lon)
                results.append(("official:\(OperationalFeedConfig.baseURL)", response))
                newHealth["official:\(OperationalFeedConfig.baseURL)"] = "ok"
            } catch {
                newHealth["official:\(OperationalFeedConfig.baseURL)"] = "error: \(error.localizedDescription)"
            }
        }

        do {
            let supabase = try await fetchFromSupabase(lat: lat, lon: lon)
            results.append(("official:supabase-ops-feed", supabase))
            newHealth["official:supabase-ops-feed"] = "ok"
        } catch {
            newHealth["official:supabase-ops-feed"] = "error: \(error.localizedDescription)"
        }

        sourceHealth = newHealth
        guard !results.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return results
    }

    private func fetchFromConfiguredProvider(baseURL: String, lat: Double, lon: Double) async throws -> PartnerOperationalFeedResponse {
        var components = URLComponents(string: "\(baseURL)/v1/ops-feed")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lon)),
            URLQueryItem(name: "radius_km", value: "80")
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let key = OperationalFeedConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PartnerOperationalFeedResponse.self, from: data)
    }

    private func fetchFromSupabase(lat: Double, lon: Double) async throws -> PartnerOperationalFeedResponse {
        var components = URLComponents(string: "\(SupabaseConfig.projectURL)/functions/v1/ops-feed")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lon)),
            URLQueryItem(name: "radius_km", value: "80")
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
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
        return try decoder.decode(PartnerOperationalFeedResponse.self, from: data)
    }

    private func mergeParkingSignals(from groups: [[PartnerParkingSignal]]) -> [PartnerParkingSignal] {
        var seen = Set<String>()
        var merged: [PartnerParkingSignal] = []
        for signal in groups.flatMap({ $0 }) {
            let key = "\(signal.locationName.lowercased())-\(String(format: "%.4f", signal.latitude))-\(String(format: "%.4f", signal.longitude))"
            if seen.contains(key) { continue }
            seen.insert(key)
            merged.append(signal)
        }
        return merged
    }

    private func mergeWeighSignals(from groups: [[PartnerWeighSignal]]) -> [PartnerWeighSignal] {
        let ranked = groups.flatMap { $0 }.sorted { weighSignalPriority($0) < weighSignalPriority($1) }
        var seen = Set<String>()
        var merged: [PartnerWeighSignal] = []
        for signal in ranked {
            let key = "\(signal.stationName.lowercased())-\(String(format: "%.4f", signal.latitude))-\(String(format: "%.4f", signal.longitude))"
            if seen.contains(key) { continue }
            seen.insert(key)
            merged.append(signal)
        }
        return merged
    }

    private func weighSignalPriority(_ signal: PartnerWeighSignal) -> Int {
        let src = (signal.source ?? "").lowercased()
        if WeighStationStatusProvenance.isOfficialSource(src) { return 0 }
        if src.contains("crowd") { return 2 }
        return 1
    }
}
