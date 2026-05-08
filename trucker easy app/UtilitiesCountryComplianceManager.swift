import Foundation
import CoreLocation
import Observation

struct TruckCountryGuidance {
    let regulationProfile: RegulationProfile
    let region: SupportedRegion
    let maxTruckSpeedKmh: Double
    let weighStationQueries: [String]
    let nearbyCategoryHints: [String: String]

    static let generic = TruckCountryGuidance(
        regulationProfile: .generic,
        region: .usa,
        maxTruckSpeedKmh: 90,
        weighStationQueries: [
            "weigh station",
            "truck scale",
            "DOT weigh station"
        ],
        nearbyCategoryHints: [:]
    )

    static func build(from profile: RegulationProfile) -> TruckCountryGuidance {
        switch profile.country {
        case .usa:
            return TruckCountryGuidance(
                regulationProfile: profile,
                region: .usa,
                maxTruckSpeedKmh: 105,
                weighStationQueries: ["weigh station", "truck scale", "DOT weigh station", "port of entry truck"],
                nearbyCategoryHints: [
                    "parking": "truck parking rest area",
                    "fuel": "diesel truck stop",
                    "repair": "truck repair service"
                ]
            )
        case .canada:
            return TruckCountryGuidance(
                regulationProfile: profile,
                region: .canada,
                maxTruckSpeedKmh: 105,
                weighStationQueries: ["weigh station", "commercial vehicle inspection", "truck scale"],
                nearbyCategoryHints: [
                    "parking": "truck parking pullout",
                    "fuel": "diesel cardlock truck stop"
                ]
            )
        case .mexico:
            return TruckCountryGuidance(
                regulationProfile: profile,
                region: .mexico,
                maxTruckSpeedKmh: 95,
                weighStationQueries: ["estacion de pesaje", "balanza camion", "weigh station"],
                nearbyCategoryHints: [
                    "parking": "paradero de camiones",
                    "fuel": "diesel tractocamion"
                ]
            )
        case .brazil:
            return TruckCountryGuidance(
                regulationProfile: profile,
                region: .brazil,
                maxTruckSpeedKmh: 90,
                weighStationQueries: ["balanca rodoviaria", "posto de pesagem", "fiscalizacao de peso caminhao"],
                nearbyCategoryHints: [
                    "parking": "patio caminhao posto",
                    "fuel": "posto diesel s10 caminhao",
                    "repair": "oficina caminhao"
                ]
            )
        case .uk:
            return TruckCountryGuidance(
                regulationProfile: profile,
                region: .uk,
                maxTruckSpeedKmh: 96,
                weighStationQueries: ["truck weighbridge", "hgv enforcement", "weigh station"],
                nearbyCategoryHints: [
                    "parking": "hgv parking",
                    "fuel": "truck diesel bunkering"
                ]
            )
        case .eu, .germany, .france:
            return TruckCountryGuidance(
                regulationProfile: profile,
                region: .europe,
                maxTruckSpeedKmh: 90,
                weighStationQueries: ["truck weigh station", "controle poids lourds", "lkw waage"],
                nearbyCategoryHints: [
                    "parking": "truck parking poids lourds lkw parkplatz",
                    "fuel": "diesel truck station",
                    "repair": "truck workshop poids lourds"
                ]
            )
        case .australia:
            return TruckCountryGuidance(
                regulationProfile: profile,
                region: .australia,
                maxTruckSpeedKmh: 100,
                weighStationQueries: ["heavy vehicle inspection", "weighbridge", "truck scale"],
                nearbyCategoryHints: [
                    "parking": "truck parking rest area",
                    "fuel": "roadhouse diesel"
                ]
            )
        case .generic:
            return .generic
        }
    }

    func query(base: String, categoryKey: String) -> String {
        guard let hint = nearbyCategoryHints[categoryKey], !hint.isEmpty else { return base }
        return "\(base) \(hint)"
    }
}

@MainActor
@Observable
final class CountryComplianceManager {
    static let shared = CountryComplianceManager()

    var guidance: TruckCountryGuidance = .generic

    private var lastRefreshDate: Date = .distantPast
    private var lastRefreshCoordinate: CLLocationCoordinate2D?
    private let refreshInterval: TimeInterval = 300
    private let refreshDistanceMeters: Double = 20_000

    private init() {}

    func refreshIfNeeded(for location: CLLocation) async {
        let now = Date()
        if now.timeIntervalSince(lastRefreshDate) < refreshInterval,
           let previous = lastRefreshCoordinate {
            let prev = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
            if location.distance(from: prev) < refreshDistanceMeters {
                return
            }
        }

        let profile = await RegulationProfile.profile(for: location.coordinate)
        guidance = TruckCountryGuidance.build(from: profile)
        lastRefreshDate = now
        lastRefreshCoordinate = location.coordinate
    }

    func nearbyQuery(base: String, categoryKey: String) -> String {
        guidance.query(base: base, categoryKey: categoryKey)
    }

    var truckSpeedLimitKmh: Double {
        guidance.maxTruckSpeedKmh
    }

    var weighQueries: [String] {
        guidance.weighStationQueries
    }

    var regulationProfile: RegulationProfile {
        guidance.regulationProfile
    }

    var recommendedRegion: SupportedRegion {
        guidance.region
    }
}
