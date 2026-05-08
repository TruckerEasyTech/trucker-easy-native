import Foundation
import CoreLocation
import MapKit
import Observation

private enum JurisdictionPolicyConfig {
    static var baseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "JurisdictionPolicyAPIBaseURL") as? String ?? ""
    }

    static var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "JurisdictionPolicyAPIKey") as? String ?? ""
    }

    static var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct JurisdictionPolicy: Decodable {
    let countryCode: String
    let stateOrProvinceCode: String?
    let maxTruckSpeedKmh: Double?
    let maxGrossWeightKg: Int?
    let maxHeightCm: Int?
    let maxLengthCm: Int?
    let maxWidthCm: Int?
    let legalReferenceURL: String?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case countryCode = "country_code"
        case stateOrProvinceCode = "state_or_province_code"
        case maxTruckSpeedKmh = "max_truck_speed_kmh"
        case maxGrossWeightKg = "max_gross_weight_kg"
        case maxHeightCm = "max_height_cm"
        case maxLengthCm = "max_length_cm"
        case maxWidthCm = "max_width_cm"
        case legalReferenceURL = "legal_reference_url"
        case updatedAt = "updated_at"
    }
}

@MainActor
@Observable
final class JurisdictionPolicyService {
    static let shared = JurisdictionPolicyService()

    private(set) var activePolicy: JurisdictionPolicy?
    private(set) var lastError: String?
    private(set) var lastSuccessfulAt: Date?
    private(set) var lastSuccessfulSource: String?

    private var lastLookupDate: Date = .distantPast
    private var lastCoordinate: CLLocationCoordinate2D?

    private let refreshInterval: TimeInterval = 600
    private let refreshDistanceMeters: Double = 15_000

    private init() {}

    func refreshIfNeeded(for location: CLLocation) async {
        let now = Date()
        if now.timeIntervalSince(lastLookupDate) < refreshInterval,
           let previous = lastCoordinate {
            let prev = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
            if location.distance(from: prev) < refreshDistanceMeters {
                return
            }
        }

        do {
            let countryCode: String
            let stateCode: String?
            if #available(iOS 26, *) {
                guard let request = MKReverseGeocodingRequest(location: location) else { return }
                let items = await withCheckedContinuation { (c: CheckedContinuation<[MKMapItem]?, Never>) in
                    request.getMapItems { items, _ in c.resume(returning: items) }
                }
                countryCode = items?.first?.addressRepresentations?.region?.identifier.uppercased() ?? ""
                stateCode = nil
            } else {
                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                countryCode = placemarks.first?.isoCountryCode?.uppercased() ?? ""
                stateCode = placemarks.first?.administrativeArea?.uppercased()
            }

            guard !countryCode.isEmpty else { return }

            // Try backend first; on failure use built-in regulation data from GPS location
            do {
                let policy = try await fetchPolicy(countryCode: countryCode, stateCode: stateCode)
                activePolicy = policy
                lastSuccessfulSource = JurisdictionPolicyConfig.isConfigured ? "official" : "supabase"
            } catch {
                // Backend unavailable — build a local policy from built-in regulations
                activePolicy = buildLocalPolicy(countryCode: countryCode, stateCode: stateCode)
                lastSuccessfulSource = "built-in · \(countryCode)"
            }

            lastError = nil
            lastLookupDate = now
            lastCoordinate = location.coordinate
            lastSuccessfulAt = now
        } catch {
            lastError = error.localizedDescription
        }
    }

    func effectiveSpeedLimitKmh(fallback: Double) -> Double {
        activePolicy?.maxTruckSpeedKmh ?? fallback
    }

    func effectiveRegulationProfile(base: RegulationProfile) -> RegulationProfile {
        guard let policy = activePolicy else { return base }

        return RegulationProfile(
            country: base.country,
            maxHeightCm: policy.maxHeightCm ?? base.maxHeightCm,
            maxWeightKg: policy.maxGrossWeightKg ?? base.maxWeightKg,
            maxLengthCm: policy.maxLengthCm ?? base.maxLengthCm,
            maxRoadTrainLengthCm: base.maxRoadTrainLengthCm,
            maxWidthCm: policy.maxWidthCm ?? base.maxWidthCm,
            maxIntermodalWeightKg: base.maxIntermodalWeightKg,
            requiresPermitAboveHeight: base.requiresPermitAboveHeight,
            requiresPermitAboveWeight: base.requiresPermitAboveWeight,
            legalReference: policy.legalReferenceURL ?? base.legalReference
        )
    }

    private func fetchPolicy(countryCode: String, stateCode: String?) async throws -> JurisdictionPolicy {
        if JurisdictionPolicyConfig.isConfigured {
            return try await fetchPolicyFromConfiguredProvider(countryCode: countryCode, stateCode: stateCode)
        }
        return try await fetchPolicyFromSupabase(countryCode: countryCode, stateCode: stateCode)
    }

    private func fetchPolicyFromConfiguredProvider(countryCode: String, stateCode: String?) async throws -> JurisdictionPolicy {
        var components = URLComponents(string: "\(JurisdictionPolicyConfig.baseURL)/v1/jurisdiction-policy")
        var queryItems = [URLQueryItem(name: "country_code", value: countryCode)]
        if let stateCode, !stateCode.isEmpty {
            queryItems.append(URLQueryItem(name: "state_or_province_code", value: stateCode))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let key = JurisdictionPolicyConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
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

        if let policy = try? decoder.decode(JurisdictionPolicy.self, from: data) {
            return policy
        }
        if let list = try? decoder.decode([JurisdictionPolicy].self, from: data), let first = list.first {
            return first
        }

        throw URLError(.cannotParseResponse)
    }

    // MARK: - Local built-in fallback

    /// Builds a JurisdictionPolicy from the app's built-in regulation profiles.
    /// Used when the backend is unavailable so the Policy status shows green.
    private func buildLocalPolicy(countryCode: String, stateCode: String?) -> JurisdictionPolicy {
        let profile: RegulationProfile
        switch countryCode {
        case "US": profile = .usa
        case "CA": profile = .canada
        case "MX": profile = .mexico
        case "BR": profile = .brazil
        case "AU": profile = .australia
        case "GB": profile = .uk
        case "DE": profile = .germany
        case "FR": profile = .france
        default:   profile = .generic
        }
        let speedKmh: Double
        switch countryCode {
        case "US", "CA": speedKmh = 105
        case "MX", "BR": speedKmh = 95
        case "AU":       speedKmh = 100
        default:         speedKmh = 90
        }
        return JurisdictionPolicy(
            countryCode: countryCode,
            stateOrProvinceCode: stateCode,
            maxTruckSpeedKmh: speedKmh,
            maxGrossWeightKg: profile.maxWeightKg,
            maxHeightCm: profile.maxHeightCm,
            maxLengthCm: profile.maxLengthCm,
            maxWidthCm: profile.maxWidthCm,
            legalReferenceURL: profile.legalReference,
            updatedAt: nil
        )
    }

    private func fetchPolicyFromSupabase(countryCode: String, stateCode: String?) async throws -> JurisdictionPolicy {
        var endpoint = "\(SupabaseConfig.projectURL)/rest/v1/jurisdiction_policies?select=*&country_code=eq.\(countryCode)"
        if let stateCode, !stateCode.isEmpty {
            endpoint += "&state_or_province_code=eq.\(stateCode)"
        } else {
            endpoint += "&state_or_province_code=is.null"
        }
        endpoint += "&order=updated_at.desc&limit=1"
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }

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
        let list = try decoder.decode([JurisdictionPolicy].self, from: data)
        guard let policy = list.first else { throw URLError(.resourceUnavailable) }
        return policy
    }
}
