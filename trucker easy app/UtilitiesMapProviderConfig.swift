import Foundation

#if canImport(MapboxMaps)
import MapboxMaps
#endif

enum MapProviderConfig {
    /// When Mapbox SPM is linked and `MBXAccessToken` is set, Horizon uses Mapbox as the map renderer.
    static var isMapboxHorizonRendererEnabled: Bool {
        #if canImport(MapboxMaps)
        let token = (Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return false }
        if token.contains("$(") { return false }
        return true
        #else
        return false
        #endif
    }

    struct ProviderHealth {
        let mapboxConfigured: Bool
    }

    static func verifyProviderHealth() -> ProviderHealth {
        let mapboxToken = (Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !mapboxToken.isEmpty, mapboxToken.contains("$(") {
            print("[ProviderHealth] ⚠️ MBXAccessToken não foi substituído no Info.plist (valor com $(...)). O target deve usar Config/TruckerEasy.debug ou .release.xcconfig como Base Configuration.")
        }

        let mapboxOk = !mapboxToken.isEmpty && !mapboxToken.contains("$(")
        let health = ProviderHealth(
            mapboxConfigured: mapboxOk
        )
        print("[ProviderHealth] Mapbox=\(health.mapboxConfigured ? "ok" : "missing")")
        #if canImport(MapboxMaps)
        print("[ProviderHealth] Horizon map renderer: \(isMapboxHorizonRendererEnabled ? "MapboxMaps" : "MapKit (token vazio no Info.plist da build)")")
        #else
        print("[ProviderHealth] Horizon map renderer: MapKit (pacote MapboxMaps não ligado ao target)")
        #endif
        return health
    }

    static func configureIfAvailable() {
        #if canImport(MapboxMaps)
        let token = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String ?? ""
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            print("[MapProviderConfig] Mapbox not configured: MBXAccessToken missing or not substituted from xcconfig")
            return
        }
        // v11: set before any MapView is created — see https://docs.mapbox.com/ios/maps/guides/install/
        MapboxOptions.accessToken = trimmed
        print("[MapProviderConfig] Mapbox token configured: \(trimmed.prefix(12))…")
        #else
        // Mapbox package not integrated; skip configuration safely
        print("[MapProviderConfig] MapboxMaps package not integrated — using Apple MapKit")
        #endif
    }
}
