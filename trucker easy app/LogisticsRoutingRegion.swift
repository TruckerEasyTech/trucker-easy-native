import CoreLocation
import Foundation

// MARK: - Macro regions (coarse geography for logging + optional Valhalla ordering)

/// Rough geographic bucket for logistics / regulation context — not a substitute for legal jurisdiction.
enum LogisticsMacroRegion: String, CaseIterable, Sendable {
    case europeAndNeighbours
    case northAmerica
    case southAmerica
    case northAfricaMiddleEast
    case subSaharanAfrica
    case asiaPacific
    case oceania
    case polarOceans
    case unknown

    /// Bounding-box classification only (no network calls). Coarse buckets for logs / UX hints.
    static func region(for coordinate: CLLocationCoordinate2D) -> LogisticsMacroRegion {
        let lat = coordinate.latitude
        let lon = coordinate.longitude

        if lat > 70 || lat < -56 { return .polarOceans }

        // South America (incl. southern cone, Amazon basin)
        if lat <= 15, lat >= -56, lon >= -82, lon <= -34 {
            return .southAmerica
        }

        // North America (US, Canada, Alaska; Mexico overlaps — still “North America” for logistics)
        if lat >= 14, lat <= 72, lon >= -168, lon <= -52 {
            return .northAmerica
        }

        // Europe + nearby Atlantic/Med (TR western part overlaps EU box — acceptable for macro label)
        if lat >= 34, lat <= 72, lon >= -11, lon <= 45 {
            return .europeAndNeighbours
        }

        // Middle East / North Africa (corridor to EU)
        if lat >= 12, lat <= 38, lon > 25, lon <= 65 {
            return .northAfricaMiddleEast
        }

        // Sub-Saharan Africa
        if lat >= -36, lat < 15, lon >= -20, lon <= 55 {
            return .subSaharanAfrica
        }

        // South / East Asia
        if lat >= -12, lat <= 55, lon > 65, lon <= 155 {
            return .asiaPacific
        }

        // Oceania / Pacific
        if lat < 0, lat >= -50, lon > 110, lon <= 180 {
            return .oceania
        }

        return .unknown
    }

    /// Midpoint between two coordinates — used for “where is this trip mostly happening”.
    static func regionAlongRoute(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> LogisticsMacroRegion {
        let mid = CLLocationCoordinate2D(
            latitude: (a.latitude + b.latitude) / 2,
            longitude: (a.longitude + b.longitude) / 2
        )
        return region(for: mid)
    }
}
