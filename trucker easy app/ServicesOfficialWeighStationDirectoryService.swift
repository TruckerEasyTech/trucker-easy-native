import Foundation
import CoreLocation
import Observation

struct OfficialWeighStation: Identifiable {
    let id: String
    let name: String
    let stateCode: String?
    let stationID: String?
    let coordinate: CLLocationCoordinate2D
    let annualTruckCount: Int?
    let activeDays: Int?
    let source: String

    func distance(from location: CLLocation) -> CLLocationDistance {
        location.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}

@MainActor
@Observable
final class OfficialWeighStationDirectoryService {
    static let shared = OfficialWeighStationDirectoryService()

    private(set) var stations: [OfficialWeighStation] = []
    private(set) var lastError: String?
    private(set) var lastSuccessfulAt: Date?
    private(set) var sourceName = "FHWA/NTAD WIM"

    private var isRefreshing = false
    private let refreshInterval: TimeInterval = 7 * 24 * 60 * 60
    private let sourceURL = URL(string: "https://services.arcgis.com/xOi1kZaI0eWDREZv/arcgis/rest/services/NTAD_Weigh_in_Motion_Stations/FeatureServer/0/query")!

    private init() {}

    func refreshIfNeeded() async {
        if isRefreshing { return }
        if let lastSuccessfulAt = lastSuccessfulAt,
           Date().timeIntervalSince(lastSuccessfulAt) < refreshInterval,
           !stations.isEmpty {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            stations = try await fetchStations()
            lastSuccessfulAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            print("[WeighDirectory] FHWA/NTAD fetch failed: \(error.localizedDescription)")
        }
    }

    func nearbyStations(near coordinate: CLLocationCoordinate2D, radiusMeters: CLLocationDistance = 40_000) async -> [OfficialWeighStation] {
        await refreshIfNeeded()
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return stations
            .map { station in (station, station.distance(from: origin)) }
            .filter { $0.1 <= radiusMeters }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }

    private func fetchStations() async throws -> [OfficialWeighStation] {
        var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "where", value: "1=1"),
            URLQueryItem(name: "outFields", value: "*"),
            URLQueryItem(name: "returnGeometry", value: "true"),
            URLQueryItem(name: "resultRecordCount", value: "2000"),
            URLQueryItem(name: "f", value: "json")
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(ArcGISFeatureCollection.self, from: data)
        return decoded.features.compactMap { feature in
            let attr = feature.attributes
            let lat = feature.geometry?.y ?? attr.double("latitude")
            let lon = feature.geometry?.x ?? attr.double("longitude")
            guard let lat = lat,
                  let lon = lon,
                  (-90...90).contains(lat),
                  (-180...180).contains(lon) else {
                return nil
            }

            let state = attr.string("state") ?? attr.string("STATE") ?? attr.string("STUSPS")
            let stationID = attr.string("station_id") ?? attr.string("STATION_ID") ?? attr.string("STNNKEY")
            let concatID = attr.string("Concat_ID") ?? attr.string("OBJECTID") ?? stationID ?? "\(lat),\(lon)"
            let name = stationID.map { "DOT WIM Station \($0)" } ?? "DOT WIM Station"

            return OfficialWeighStation(
                id: concatID,
                name: name,
                stateCode: state,
                stationID: stationID,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                annualTruckCount: attr.int("Counts_Year"),
                activeDays: attr.int("Num_Days_Active"),
                source: sourceName
            )
        }
    }
}

private struct ArcGISFeatureCollection: Decodable {
    let features: [ArcGISFeature]
}

private struct ArcGISFeature: Decodable {
    let attributes: [String: ArcGISValue]
    let geometry: ArcGISGeometry?
}

private struct ArcGISGeometry: Decodable {
    let x: Double?
    let y: Double?
}

private enum ArcGISValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .null
        }
    }
}

private extension Dictionary where Key == String, Value == ArcGISValue {
    func string(_ key: String) -> String? {
        guard let value = self[key] else { return nil }
        switch value {
        case .string(let string): return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case .number(let number): return String(Int(number))
        case .bool(let bool): return bool ? "true" : "false"
        case .null: return nil
        }
    }

    func double(_ key: String) -> Double? {
        guard let value = self[key] else { return nil }
        switch value {
        case .number(let number): return number
        case .string(let string): return Double(string)
        case .bool, .null: return nil
        }
    }

    func int(_ key: String) -> Int? {
        guard let value = self[key] else { return nil }
        switch value {
        case .number(let number): return Int(number)
        case .string(let string): return Int(string)
        case .bool, .null: return nil
        }
    }
}
