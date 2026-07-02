//
//  ServicesRouteSignageService.swift
//  trucker easy app
//
//  Sinalização viária AO LONGO da rota (semáforos + placas de PARE) para a navegação na cidade.
//  Reusa o mesmo pipeline de POI dos truck stops: OSM → poi_places → places_near (Supabase).
//  A diferença é o FILTRO DE CORREDOR: só entram pontos que caem em cima da polyline da rota
//  ativa e dentro de um raio curto à frente — assim o GPS "reconhece a rota e as sinalizações"
//  em vez de poluir o mapa com todos os semáforos da cidade.
//

import Foundation
import CoreLocation

// MARK: - Modelo

/// Um ponto de sinalização (semáforo / PARE) que pertence ao corredor da rota ativa.
struct RouteSignageItem: Identifiable, Equatable {
    enum Kind: String {
        case trafficSignal   // OSM highway=traffic_signals
        case stop            // OSM highway=stop
        case railCrossing    // OSM railway=level_crossing — passagem de nível (crítico p/ caminhão preso no trilho)
        case lowBridge       // FHWA NBI — ponte com altura livre restritiva (<16ft); alerta por altura do perfil
    }

    let id: String          // estável por tipo+coordenada (~1 m) → render incremental sem churn
    let kind: Kind
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double
    /// Ponte baixa: altura livre REAL do NBI (metros / texto "12'4\""). nil nos demais tipos.
    var clearanceMeters: Double? = nil
    var clearanceText: String? = nil

    init(kind: Kind, coordinate: CLLocationCoordinate2D, distanceMeters: Double,
         clearanceMeters: Double? = nil, clearanceText: String? = nil) {
        self.kind = kind
        self.coordinate = coordinate
        self.distanceMeters = distanceMeters
        self.clearanceMeters = clearanceMeters
        self.clearanceText = clearanceText
        let lat = (coordinate.latitude * 100_000).rounded() / 100_000
        let lon = (coordinate.longitude * 100_000).rounded() / 100_000
        self.id = "\(kind.rawValue)|\(lat)|\(lon)"
    }

    static func == (lhs: RouteSignageItem, rhs: RouteSignageItem) -> Bool { lhs.id == rhs.id }
}

// MARK: - Serviço

@MainActor
@Observable
final class RouteSignageService {
    static let shared = RouteSignageService()
    private init() {}

    /// Sinalização que caiu DENTRO do corredor da rota, à frente do motorista (mais próximo primeiro).
    private(set) var onRouteSignage: [RouteSignageItem] = []

    /// Corredor: um nó OSM só conta como "na rota" se estiver a no máximo isto da polyline.
    private let corridorMeters: Double = 28
    /// Janela curta à frente (cidade) — limita densidade e mantém só o que é relevante agora.
    private let lookaheadMeters: Double = 1_500
    /// Raio da busca de rede (um pouco maior que a janela para reaproveitar entre ticks).
    /// 5km: ponte baixa precisa entrar no corredor ANTES do aviso de voz a ~1.8km.
    private let fetchRadiusMeters: Double = 5_000

    private var lastFetchAt: Date = .distantPast
    private var lastFetchLocation: CLLocation?
    private var isFetching = false
    /// Cooldown do fallback Overpass (educado com o serviço público) — só quando a poi_places não cobre a área.
    private var lastOverpassAt: Date = .distantPast

    func clear() {
        onRouteSignage = []
        lastFetchLocation = nil
        lastFetchAt = .distantPast
    }

    /// Chamar a cada update de GPS durante a navegação. Debounce de rede: 250 m OU 15 s.
    /// Entre buscas, só recalcula distâncias (barato) para os ícones sumirem ao passar.
    func refresh(location: CLLocation, routeCoordinates: [CLLocationCoordinate2D]) {
        guard SupabaseConfig.isConfigured, routeCoordinates.count >= 2 else { return }

        let now = Date()
        if let prev = lastFetchLocation,
           location.distance(from: prev) < 250,
           now.timeIntervalSince(lastFetchAt) < 15 {
            recomputeDistances(from: location)
            return
        }
        guard !isFetching else { return }
        isFetching = true
        lastFetchLocation = location
        lastFetchAt = now

        Task { @MainActor in
            defer { isFetching = false }
            do {
                let rows = try await PoiPlacesService.shared.fetchPlacesNear(
                    location: location,
                    radiusMeters: fetchRadiusMeters,
                    poiTypes: ["traffic_signals", "stop", "rail_crossing", "low_bridge"],
                    limit: 80
                )
                var merged = Self.filterToCorridor(
                    rows: rows,
                    user: location,
                    route: routeCoordinates,
                    corridorMeters: corridorMeters,
                    lookaheadMeters: lookaheadMeters
                )
                // Overpass roda SEMPRE (online + cooldown 60s) — é a ÚNICA fonte de passagem de trem
                // (railway=level_crossing NÃO está na poi_places) e cobre semáforos/PARE onde o ingest
                // não rodou (densos demais p/ varredura nacional). MERGE + dedup com a base. Best-effort.
                if NetworkReachability.shared.isOnline,
                   now.timeIntervalSince(lastOverpassAt) > 60 {
                    lastOverpassAt = now
                    if let live = try? await Self.fetchSignalsFromOverpass(
                        user: location, route: routeCoordinates,
                        corridorMeters: corridorMeters, lookaheadMeters: lookaheadMeters,
                        searchRadiusMeters: fetchRadiusMeters
                    ), !live.isEmpty {
                        var seen = Set(merged.map(\.id))
                        for item in live where seen.insert(item.id).inserted { merged.append(item) }
                        merged.sort { $0.distanceMeters < $1.distanceMeters }
                    }
                }
                onRouteSignage = merged
            } catch {
                #if DEBUG
                print("[Signage] places_near falhou: \(error.localizedDescription)")
                #endif
            }
        }
    }

    private func recomputeDistances(from location: CLLocation) {
        guard !onRouteSignage.isEmpty else { return }
        onRouteSignage = onRouteSignage
            .map { item in
                let d = location.distance(from: CLLocation(latitude: item.coordinate.latitude,
                                                            longitude: item.coordinate.longitude))
                return RouteSignageItem(kind: item.kind, coordinate: item.coordinate, distanceMeters: d)
            }
            .filter { $0.distanceMeters <= lookaheadMeters }
            .sorted { $0.distanceMeters < $1.distanceMeters }
    }

    // MARK: - Filtro de corredor

    private static func filterToCorridor(
        rows: [PlacesNearRow],
        user: CLLocation,
        route: [CLLocationCoordinate2D],
        corridorMeters: Double,
        lookaheadMeters: Double
    ) -> [RouteSignageItem] {
        rows.compactMap { row -> RouteSignageItem? in
            let kind: RouteSignageItem.Kind
            switch row.poi_type {
            case "traffic_signals": kind = .trafficSignal
            case "stop":            kind = .stop
            case "rail_crossing":   kind = .railCrossing
            case "low_bridge":      kind = .lowBridge
            default:                return nil
            }
            let coord = CLLocationCoordinate2D(latitude: row.lat, longitude: row.lon)
            let userDist = row.distance_m
                ?? user.distance(from: CLLocation(latitude: row.lat, longitude: row.lon))
            // Ponte baixa: janela maior (aviso de voz a ~1.8km precisa dela no corredor antes)
            // e corredor mais largo (o ponto NBI é a ESTRUTURA, pode ficar ~40m do eixo da via).
            let maxAhead = kind == .lowBridge ? 3_200.0 : lookaheadMeters
            let maxCorridor = kind == .lowBridge ? 45.0 : corridorMeters
            guard userDist <= maxAhead else { return nil }
            guard distanceToPolyline(coord, route) <= maxCorridor else { return nil }
            return RouteSignageItem(kind: kind, coordinate: coord, distanceMeters: userDist,
                                    clearanceMeters: row.tags?.clearance_m,
                                    clearanceText: row.tags?.clearance_ftin)
        }
        .sorted { $0.distanceMeters < $1.distanceMeters }
    }

    /// Menor distância (m) de um ponto à polyline (mínimo ponto-segmento), com projeção
    /// equiretangular local ancorada no ponto — precisão de sobra na escala de quadra urbana.
    private static func distanceToPolyline(_ p: CLLocationCoordinate2D,
                                           _ line: [CLLocationCoordinate2D]) -> Double {
        guard line.count >= 2 else { return .infinity }
        let mPerDegLat = 111_132.0
        let mPerDegLon = 111_320.0 * cos(p.latitude * .pi / 180)
        func proj(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            ((c.longitude - p.longitude) * mPerDegLon, (c.latitude - p.latitude) * mPerDegLat)
        }
        var best = Double.infinity
        for i in 0..<(line.count - 1) {
            let a = proj(line[i])
            let b = proj(line[i + 1])
            let dx = b.x - a.x
            let dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? max(0, min(1, -(a.x * dx + a.y * dy) / len2)) : 0
            let cx = a.x + t * dx
            let cy = a.y + t * dy
            let d = (cx * cx + cy * cy).squareRoot()
            if d < best { best = d }
        }
        return best
    }

    // MARK: - Fallback Overpass (OSM ao vivo, on-demand) — semáforo/PARE no corredor
    private struct OverpassResponse: Decodable {
        struct Element: Decodable { let lat: Double?; let lon: Double?; let tags: [String: String]? }
        let elements: [Element]
    }

    /// Busca semáforos/PARE reais do OSM via Overpass no bbox do corredor próximo. Best-effort:
    /// qualquer falha/timeout → retorna vazio (o chamador mantém o comportamento atual). NÃO fabrica.
    private static func fetchSignalsFromOverpass(
        user: CLLocation,
        route: [CLLocationCoordinate2D],
        corridorMeters: Double,
        lookaheadMeters: Double,
        searchRadiusMeters: Double
    ) async throws -> [RouteSignageItem] {
        let near = route.filter {
            user.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= searchRadiusMeters
        }
        guard near.count >= 2,
              let south = near.map(\.latitude).min(), let north = near.map(\.latitude).max(),
              let west = near.map(\.longitude).min(), let east = near.map(\.longitude).max() else { return [] }

        let bbox = "\(south),\(west),\(north),\(east)"
        let query = "[out:json][timeout:8];(node[\"highway\"=\"traffic_signals\"](\(bbox));node[\"highway\"=\"stop\"](\(bbox));node[\"railway\"=\"level_crossing\"](\(bbox)););out body;"
        guard let url = URL(string: "https://overpass-api.de/api/interpreter"),
              let body = "data=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")".data(using: .utf8) else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.httpBody = body
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        let decoded = try JSONDecoder().decode(OverpassResponse.self, from: data)

        return decoded.elements.compactMap { el -> RouteSignageItem? in
            guard let lat = el.lat, let lon = el.lon else { return nil }
            let kind: RouteSignageItem.Kind
            if el.tags?["railway"] == "level_crossing" {
                kind = .railCrossing
            } else {
                switch el.tags?["highway"] {
                case "traffic_signals": kind = .trafficSignal
                case "stop":            kind = .stop
                default:                return nil
                }
            }
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let userDist = user.distance(from: CLLocation(latitude: lat, longitude: lon))
            guard userDist <= lookaheadMeters else { return nil }
            guard distanceToPolyline(coord, route) <= corridorMeters else { return nil }
            return RouteSignageItem(kind: kind, coordinate: coord, distanceMeters: userDist)
        }
        .sorted { $0.distanceMeters < $1.distanceMeters }
    }
}
