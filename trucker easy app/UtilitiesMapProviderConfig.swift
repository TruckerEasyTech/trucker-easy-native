import Foundation

#if canImport(MapboxMaps)
import MapboxMaps
#endif

enum MapProviderConfig {

    // MARK: - Token helpers

    /// Lê e valida o MBXAccessToken do Info.plist.
    /// Retorna nil se não encontrado, não substituído (contém "$(") ou não parece um token Mapbox real.
    private static var infoPlisToken: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains("$(") else { return nil }
        // Token Mapbox público começa com "pk." ou "sk." — rejeita placeholders aleatórios.
        guard t.hasPrefix("pk.") || t.hasPrefix("sk.") else { return nil }
        return t
    }

    // MARK: - Enabled flag

    /// True quando Mapbox está disponível E o token foi configurado com sucesso.
    /// Checa `MapboxOptions.accessToken` (setado por configureIfAvailable) primeiro;
    /// fallback no Info.plist para garantir robustez caso a ordem de init mude.
    static var isMapboxHorizonRendererEnabled: Bool {
        #if canImport(MapboxMaps)
        guard !AppAccessPolicy.useMapKitHorizonMap else { return false }
        // Fonte primária: token já validado e aplicado por configureIfAvailable().
        if !MapboxOptions.accessToken.isEmpty { return true }
        // Fallback: lê diretamente do Info.plist (Mapbox v11 tb lê automaticamente).
        return infoPlisToken != nil
        #else
        return false
        #endif
    }

    // MARK: - Configuration

    /// Aplica o token no SDK antes de qualquer MapView ser criado.
    /// Deve ser chamado em app init, antes do SwiftUI body renderizar.
    static func configureIfAvailable() {
        #if canImport(MapboxMaps)
        guard let token = infoPlisToken else {
            #if DEBUG
            let raw = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String ?? "<nenhum>"
            print("[MapProviderConfig] ⚠️ Mapbox NÃO configurado. MBXAccessToken='\(raw.prefix(20))' — verifique xcconfig como Base Configuration no target.")
            #endif
            return
        }
        // v11: deve ser setado antes de qualquer MapView ser criado.
        MapboxOptions.accessToken = token
        #if DEBUG
        print("[MapProviderConfig] ✅ Mapbox token configurado: \(token.prefix(12))…")
        #endif
        #else
        #if DEBUG
        print("[MapProviderConfig] MapboxMaps não integrado — usando MapKit.")
        #endif
        #endif
    }

    // MARK: - Health check (diagnóstico, não afeta funcionalidade)

    struct ProviderHealth {
        let mapboxConfigured: Bool
    }

    @discardableResult
    static func verifyProviderHealth() -> ProviderHealth {
        let health = ProviderHealth(mapboxConfigured: isMapboxHorizonRendererEnabled)
        #if DEBUG
        print("[ProviderHealth] Mapbox=\(health.mapboxConfigured ? "ok ✅" : "missing ⚠️") · renderer=\(health.mapboxConfigured ? "MapboxMaps" : "MapKit")")
        #endif
        return health
    }
}
