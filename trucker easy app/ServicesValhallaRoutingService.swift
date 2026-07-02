// ServicesValhallaRoutingService.swift
// trucker easy app
//
// Valhalla open-source truck routing — self-hosted, zero per-user cost.
//
// INFRASTRUCTURE SETUP (one-time, ~$50/month fixed):
//   1. Spin up a server (DigitalOcean 8GB Droplet or AWS c5.large)
//   2. docker pull valhalla/valhalla:run-latest
//   3. Download OSM data: wget https://download.geofabrik.de/north-america/us-latest.osm.pbf
//   4. Build truck routing tiles:
//      docker run -v /data:/data valhalla/valhalla:run-latest \
//        valhalla_build_config --mjolnir-tile-dir /data/tiles > valhalla.json
//      docker run -v /data:/data valhalla/valhalla:run-latest \
//        valhalla_build_tiles -c valhalla.json /data/us-latest.osm.pbf
//   5. Run: docker run -d -p 8002:8002 -v /data:/data valhalla/valhalla:run-latest
//   DEV (Mac + iPhone, Europa): docker run -d -p 8002:8002 --name valhalla-europe \
//        -e tile_urls=https://download.geofabrik.de/europe-latest.osm.pbf \
//        ghcr.io/gis-ops/docker-valhalla/valhalla:latest
//        (middleware Python :8003 — ver README em backend/quantum-routing)
//   6. Set Info.plist key "ValhallaServerURL" = "https://your-server.com"
//
// COST COMPARISON:
//   Commercial truck APIs: ~$10/driver/month  → 100 drivers = $1,000/month variable
//   Valhalla (own):    ~$50-100/month fixed → 1,000 drivers = $0.05-0.10/driver
//
// API DOCS: https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/

import Foundation
import CoreLocation
import MapKit

// MARK: - Valhalla Routing Service

@MainActor
@Observable
final class ValhallaRoutingService {
    static let shared = ValhallaRoutingService()

    /// LAN Valhalla: bounded retries + backoff (below); timeouts tolerate cold Docker / slow LAN.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 22
        config.timeoutIntervalForResource = 48
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private init() {}

    /// Primary Valhalla base URL from Info.plist (`ValhallaServerURL`).
    var serverURL: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "ValhallaServerURL") as? String ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "||", with: "//")
    }

    /// Optional list from `ValhallaServerURLs` (comma-separated). Same `||` rule as other xcconfig URLs.
    /// When non-empty, each entry is tried in order until one returns HTTP 200 for `/route`.
    /// When empty, `serverURL` alone is used.
    /// Production fallback when xcconfig secrets are missing on device builds.
    private static let productionFallbackBaseURL = "https://valhalla.truckereasy.com"

    var serverBaseURLs: [String] {
        let listRaw = Bundle.main.object(forInfoDictionaryKey: "ValhallaServerURLs") as? String ?? ""
        let parts = listRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "||", with: "//") }
            .filter { !$0.isEmpty && !$0.contains("$(") }
        if !parts.isEmpty { return parts }
        let single = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !single.isEmpty, !single.contains("$(") { return [single] }
        return [Self.productionFallbackBaseURL]
    }

    /// Same URLs as `serverBaseURLs`, but **HTTPS bases are tried before HTTP** when multiple entries exist.
    /// Use `VALHALLA_SERVER_URLS = https:||prod.example.com,http:||192.168.x.x:8002` so fleet/global routing wins over LAN dev.
    var prioritizedServerBaseURLs: [String] {
        Self.prioritizeValhallaBaseURLsByScheme(serverBaseURLs)
    }

    /// Stable ordering: HTTPS (tier 0) before HTTP (tier 1); original xcconfig order preserved within each tier.
    private static func prioritizeValhallaBaseURLsByScheme(_ urls: [String]) -> [String] {
        guard urls.count > 1 else { return urls }
        return urls.enumerated()
            .sorted { lhs, rhs in
                let tl = schemeTier(lhs.element)
                let tr = schemeTier(rhs.element)
                if tl != tr { return tl < tr }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func schemeTier(_ raw: String) -> Int {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "||", with: "//")
        guard let scheme = URL(string: normalized)?.scheme?.lowercased() else { return 10 }
        switch scheme {
        case "https": return 0
        case "http": return 1
        default: return 5
        }
    }

    /// Same source as the merged app Info.plist — fails closed if xcconfig did not substitute URLs.
    var isAvailable: Bool {
        !serverBaseURLs.isEmpty
    }

    // MARK: - Calculate Truck Route

    /// Calls your self-hosted Valhalla server and returns a TruckRoute (app's internal model).
    /// Valhalla "truck" costing respects height, weight, length, axle limits, and hazmat.
    func calculateTruckRoute(
        from origin: CLLocation,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        profile: TruckProfile,
        avoidTolls: Bool = false,
        via: CLLocationCoordinate2D? = nil
    ) async throws -> TruckRoute {
        guard let first = prioritizedServerBaseURLs.first else {
            throw ValhallaError.serverNotConfigured
        }
        return try await calculateTruckRoute(
            from: origin,
            to: destination,
            destinationName: destinationName,
            profile: profile,
            avoidTolls: avoidTolls,
            serverBaseURL: first,
            via: via
        )
    }

    /// Same as `calculateTruckRoute` but targets one specific Valhalla base (used when cycling multiple servers).
    func calculateTruckRoute(
        from origin: CLLocation,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        profile: TruckProfile,
        avoidTolls: Bool,
        serverBaseURL: String,
        via: CLLocationCoordinate2D? = nil
    ) async throws -> TruckRoute {
        let base = serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            throw ValhallaError.serverNotConfigured
        }

        let normalizedBase = Self.normalizeValhallaBaseURL(base)
        guard let url = URL(string: "\(normalizedBase)/route") else {
            throw ValhallaError.serverNotConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try buildRequestBody(
            from: origin.coordinate,
            to: destination,
            profile: profile,
            avoidTolls: avoidTolls,
            via: via
        )

        let hostLabel: String
        if let h = url.host { hostLabel = h } else { hostLabel = normalizedBase.prefix(24).description }
        #if DEBUG
        print("[Valhalla] Requesting truck route to \(destinationName) via \(hostLabel)...")
        #endif

        let maxAttempts = 3
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await session.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    throw ValhallaError.invalidResponse
                }
                guard http.statusCode == 200 else {
                    let body = String(data: data, encoding: .utf8) ?? "empty"
                    #if DEBUG
                    print("[Valhalla] HTTP \(http.statusCode): \(body.prefix(500))")
                    #endif
                    throw ValhallaError.serverError(http.statusCode)
                }

                let valhalla: ValhallaRouteResponse
                do {
                    valhalla = try JSONDecoder().decode(ValhallaRouteResponse.self, from: data)
                } catch {
                    #if DEBUG
                    let snippet = String(data: data.prefix(400), encoding: .utf8) ?? "binary"
                    print("[Valhalla] JSON decode failed: \(error.localizedDescription) body=\(snippet)")
                    #endif
                    throw error
                }
                let route = try parseRoute(valhalla, destinationName: destinationName)
                #if DEBUG
                print("[Valhalla] ✅ Route: \(String(format: "%.1f", route.distanceMiles)) mi, \(Int(route.durationSeconds / 60)) min, \(route.steps.count) steps · \(hostLabel)")
                #endif
                return route
            } catch {
                lastError = error
                let retry = attempt < maxAttempts && Self.shouldRetryValhallaTransport(error)
                #if DEBUG
                if retry {
                    print("[Valhalla] attempt \(attempt)/\(maxAttempts) failed (\(error.localizedDescription)) — retrying…")
                } else {
                    Self.logValhallaConnectionHint(baseURL: normalizedBase, error: error)
                }
                #endif
                if retry {
                    try await Task.sleep(nanoseconds: Self.retryBackoffNanoseconds(attempt: attempt))
                    continue
                }
                throw error
            }
        }
        throw lastError ?? ValhallaError.invalidResponse
    }

    /// Removes trailing slashes so `/route` is never `//route`.
    private static func normalizeValhallaBaseURL(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Retry transport errors where a short backoff often helps (Wi‑Fi, Docker restart, ARP, transient refused).
    /// Does not retry HTTP 4xx/5xx from Valhalla (handled separately — no infinite loop on bad tiles).
    private static func shouldRetryValhallaTransport(_ error: Error) -> Bool {
        let ns = error as NSError

        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotLoadFromNetwork,
                 NSURLErrorDataNotAllowed:
                return true
            default:
                break
            }
        }

        var chain: NSError? = ns
        while let cur = chain {
            if cur.domain == NSPOSIXErrorDomain, cur.code == 61 { return true } // ECONNREFUSED
            chain = cur.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    /// 0.45s → ~2.9s capped — spreads attempts across Docker / TCP settle without endless waits.
    private static func retryBackoffNanoseconds(attempt: Int) -> UInt64 {
        let baseMs: UInt64 = 450
        let factor = UInt64(min(attempt * attempt, 42))
        let ms = min(baseMs * factor, 2900)
        return ms * 1_000_000
    }

    #if DEBUG
    private static func logValhallaConnectionHint(baseURL: String, error: Error) {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return }
        let host = URL(string: baseURL)?.host ?? baseURL
        switch ns.code {
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
            print("""
            [Valhalla] ⚠️ Cannot reach \(host). Checklist:
              • Valhalla running: `docker ps` (port 8002) or process listening on 8002
              • Bind all interfaces: container `-p 8002:8002`, not only 127.0.0.1 on the phone's network path
              • Same Wi‑Fi as iPhone; Mac LAN IP still matches xcconfig (run: ipconfig getifaddr en0)
              • macOS Firewall: allow incoming on port 8002 for dev
              • Production: use HTTPS URL in VALHALLA_SERVER_URL (see backend/valhalla-production/README.md)
            """)
        default:
            break
        }
    }
    #endif

    // MARK: - Build Request Body

    private func buildRequestBody(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        profile: TruckProfile,
        avoidTolls: Bool,
        via: CLLocationCoordinate2D? = nil
    ) throws -> Data {
        // Valhalla truck costing options — maps directly to TruckProfile dimensions
        var costingOptions: [String: Any] = [
            "height": profile.heightMeters,             // meters
            "width":  profile.widthMeters,              // meters (driver profile; defaults to 2.59 = 8'6")
            "length": profile.lengthMeters,             // meters
            "weight": profile.weightTonnes * 0.907185,  // short tons → metric tonnes
            "axle_load": profile.axleWeightTonnes * 0.907185,  // short tons → metric tonnes per axle
            // 🎯 FIX "SAÍDAS FANTASMA" (road test 01/07, Ogallala NE): sem isto o Valhalla 3.5
            // dava custo IGUAL à I-80 e às paralelas (US-30/links) e saía da interstate em quase
            // toda interchange — "Take exit 133 toward Roscoe" numa viagem NE→NJ (+130mi, 234
            // manobras). `use_truck_route:1` dá preferência aos corredores hgv=designated (rede
            // nacional de caminhão: interstates) → rota fica na I-80 igual Trucker Path.
            // VALIDADO no Valhalla prod: 1583.7mi/234 manobras → 1561.2mi/70 manobras, desvio
            // exit-133 eliminado. (curl de verificação em docs/EXIT_GUIDANCE_VALIDATION.md)
            "use_truck_route": 1.0
        ]

        if avoidTolls {
            costingOptions["toll_booth_penalty"] = 9999
        }

        // Hazmat flag — if truck carries hazmat, Valhalla routes around restrictions
        if profile.hasHazmat {
            costingOptions["hazmat"] = true
        }

        // WAYPOINT ACEITO PELO MOTORISTA (parada de diesel sugerida): tipo "through" — a rota
        // PASSA pelo posto sem virar multi-destino (sem "you have arrived" no meio da viagem).
        var locations: [[String: Any]] = [["lon": origin.longitude, "lat": origin.latitude, "type": "break"]]
        if let via {
            locations.append(["lon": via.longitude, "lat": via.latitude, "type": "through", "radius": 300])
        }
        locations.append(["lon": destination.longitude, "lat": destination.latitude, "type": "break"])
        let body: [String: Any] = [
            "locations": locations,
            "costing": "truck",
            "costing_options": ["truck": costingOptions],
            // type 0 = depart now. Required for Valhalla to apply time-conditional
            // restrictions (e.g. "no trucks 7–9am"); omitting it ignores them entirely.
            "date_time": ["type": 0],
            "directions_options": [
                "units": "miles",
                "language": Self.valhallaInstructionLanguageTag()
            ],
            "shape_match": "walk_or_snap",
            // Fase 1.2: pede até 2 rotas alternativas (o "corredor") pro reroute offline.
            "alternates": 2
        ]

        return try JSONSerialization.data(withJSONObject: body)
    }

    /// BCP 47 tag for Valhalla `directions_options.language` — follows driver language from app settings when possible.
    private static func valhallaInstructionLanguageTag() -> String {
        if let raw = UserDefaults.standard.string(forKey: "selectedLanguage"),
           let lang = AppLanguage.allCases.first(where: { $0.rawValue == raw }) {
            let c = lang.code
            if c == "es-419" { return "es-MX" }
            if c == "pt-BR" { return "pt-BR" }
            if c == "es-ES" { return "es-ES" }
            return c.replacingOccurrences(of: "_", with: "-")
        }
        return Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    }

    // MARK: - Parse Valhalla Response → TruckRoute

    private func parseRoute(_ response: ValhallaRouteResponse, destinationName: String) throws -> TruckRoute {
        let trip = response.trip

        guard !trip.legs.isEmpty else { throw ValhallaError.noRoute }

        // Decode all coordinates from all legs (Valhalla encodes each leg's shape as polyline6)
        var allCoordinates: [CLLocationCoordinate2D] = []
        var allSteps: [RouteStep] = []

        for leg in trip.legs {
            let coords = StandardPolylineDecoder.decode(leg.shape, precision: 6)
            allCoordinates.append(contentsOf: coords)

            for maneuver in leg.maneuvers {
                // Skip trivial "depart" / "arrive" with no instruction content
                let instruction = maneuver.instruction.trimmingCharacters(in: .whitespaces)
                guard !instruction.isEmpty else { continue }

                // Shield de saída SÓ na manobra de saída/rampa de verdade (tipos Valhalla 17–21).
                // O Valhalla carrega o nº via consecutive_count pro passo "Continue" (tipo 8) seguinte;
                // mostrar "EXIT 282" ali (após já sair) seria redundante. Validado na resposta real.
                let isExitManeuver = (17...21).contains(maneuver.type)
                allSteps.append(RouteStep(
                    instruction: instruction,
                    distanceMeters: maneuver.length * 1609.34,    // miles → meters
                    durationSeconds: maneuver.time,
                    maneuver: ValhallaManeuverType(rawValue: maneuver.type)?.instruction ?? instruction,
                    exitNumber: isExitManeuver ? maneuver.sign?.exitNumberText : nil,   // saída EXATA do Valhalla (não regex)
                    exitToward: isExitManeuver ? maneuver.sign?.exitTowardText : nil
                ))
            }
        }

        guard !allCoordinates.isEmpty else { throw ValhallaError.emptyPolyline }

        let totalDistanceMeters = Double(trip.summary.length) * 1609.34   // miles → meters
        let totalDurationSeconds = trip.summary.time

        var route = TruckRoute(
            coordinates: allCoordinates,
            steps: allSteps,
            distanceMeters: totalDistanceMeters,
            durationSeconds: totalDurationSeconds,
            destinationName: destinationName,
            truckNotices: extractNotices(from: trip, legShapes: trip.legs.map(\.shape))
        )

        let tollEstimate = estimateTolls(from: trip)
        route.tollCostUSD = tollEstimate.totalCost
        route.tollCurrency = tollEstimate.currency
        route.tollPoints = tollEstimate.points

        // Fase 1.2: anexa o corredor (alternativas) pro reroute offline.
        if let alts = response.alternates, !alts.isEmpty {
            route.corridorAlternates = alts.compactMap { parseAlternateTrip($0.trip, destinationName: destinationName) }
        }

        return route
    }

    /// Geometria + passos de um trip ALTERNATIVO — só o necessário pra navegar offline
    /// (sem tolls/notices, que não são críticos pra um desvio de emergência sem sinal).
    private func parseAlternateTrip(_ trip: ValhallaTrip, destinationName: String) -> TruckRoute? {
        guard !trip.legs.isEmpty else { return nil }
        var coords: [CLLocationCoordinate2D] = []
        var steps: [RouteStep] = []
        for leg in trip.legs {
            coords.append(contentsOf: StandardPolylineDecoder.decode(leg.shape, precision: 6))
            for m in leg.maneuvers {
                let instr = m.instruction.trimmingCharacters(in: .whitespaces)
                guard !instr.isEmpty else { continue }
                let isExit = (17...21).contains(m.type)
                steps.append(RouteStep(
                    instruction: instr,
                    distanceMeters: m.length * 1609.34,
                    durationSeconds: m.time,
                    maneuver: ValhallaManeuverType(rawValue: m.type)?.instruction ?? instr,
                    exitNumber: isExit ? m.sign?.exitNumberText : nil,
                    exitToward: isExit ? m.sign?.exitTowardText : nil
                ))
            }
        }
        guard !coords.isEmpty else { return nil }
        return TruckRoute(
            coordinates: coords,
            steps: steps,
            distanceMeters: Double(trip.summary.length) * 1609.34,
            durationSeconds: trip.summary.time,
            destinationName: destinationName,
            truckNotices: []
        )
    }

    // MARK: - Toll Estimation (from Valhalla toll_booth flags)

    private struct TollEstimate {
        let totalCost: Double
        let currency: String
        let points: [TollPoint]
    }

    /// Estimates toll costs from Valhalla maneuver data. Valhalla marks toll booth
    /// maneuvers and summary-level `has_toll`. Costs are averaged per-booth by region.
    /// This replaces the need for TollGuru or any paid toll API.
    private func estimateTolls(from trip: ValhallaTrip) -> TollEstimate {
        guard trip.summary.hasToll == true else {
            return TollEstimate(totalCost: 0, currency: "USD", points: [])
        }

        var tollBooths: [TollPoint] = []
        for leg in trip.legs {
            for maneuver in leg.maneuvers where maneuver.tollBooth == true {
                let name = maneuver.instruction.isEmpty ? "Toll Plaza" : maneuver.instruction
                tollBooths.append(TollPoint(name: name, cost: 0, coordinate: nil))
            }
        }

        let boothCount = max(tollBooths.count, 1)
        let distanceMiles = trip.summary.length

        let region = UserDefaults.standard.string(forKey: "selectedRegion") ?? "us"
        let (costPerBooth, currency) = Self.regionalTollRate(region: region, distanceMiles: distanceMiles, boothCount: boothCount)

        var points: [TollPoint] = []
        for booth in tollBooths {
            points.append(TollPoint(name: booth.name, cost: costPerBooth, coordinate: booth.coordinate))
        }

        if points.isEmpty && trip.summary.hasToll == true {
            let estimatedCost = Self.distanceBasedTollEstimate(distanceMiles: distanceMiles, region: region)
            points.append(TollPoint(name: "Toll Road", cost: estimatedCost, coordinate: nil))
            return TollEstimate(totalCost: estimatedCost, currency: currency, points: points)
        }

        let total = points.reduce(0) { $0 + $1.cost }
        return TollEstimate(totalCost: total, currency: currency, points: points)
    }

    /// Average toll booth cost by region for Class 8 trucks (5+ axles).
    private static func regionalTollRate(region: String, distanceMiles: Double, boothCount: Int) -> (Double, String) {
        switch region.lowercased() {
        case "us", "northamerica":
            return (5.50, "USD")
        case "ca", "canada":
            return (7.00, "CAD")
        case "br", "brazil":
            return (15.00, "BRL")
        case "eu", "europe":
            return (8.00, "EUR")
        case "mx", "mexico":
            return (120.00, "MXN")
        default:
            return (5.50, "USD")
        }
    }

    /// Fallback: when Valhalla marks `has_toll` but no individual booth maneuvers,
    /// estimate based on distance (typical US interstate toll rate for trucks).
    private static func distanceBasedTollEstimate(distanceMiles: Double, region: String) -> Double {
        let ratePerMile: Double
        switch region.lowercased() {
        case "us", "northamerica": ratePerMile = 0.25
        case "ca", "canada":      ratePerMile = 0.30
        case "br", "brazil":      ratePerMile = 0.80
        case "eu", "europe":      ratePerMile = 0.35
        case "mx", "mexico":      ratePerMile = 4.00
        default:                   ratePerMile = 0.25
        }
        return (distanceMiles * ratePerMile).rounded(.up)
    }

    // MARK: - Extract Truck Restriction Notices

    private func extractNotices(from trip: ValhallaTrip, legShapes: [String]) -> [TruckRouteNotice] {
        var notices: [TruckRouteNotice] = []
        var seenKeys = Set<String>()

        for (legIndex, leg) in trip.legs.enumerated() {
            let shape = legIndex < legShapes.count ? legShapes[legIndex] : leg.shape
            let legCoordinates = StandardPolylineDecoder.decode(shape, precision: 6)

            for (maneuverIndex, maneuver) in leg.maneuvers.enumerated() {
                guard let notice = noticeFromManeuver(
                    maneuver,
                    maneuverIndex: maneuverIndex,
                    allManeuvers: leg.maneuvers,
                    legCoordinates: legCoordinates
                ) else {
                    continue
                }
                let lat = notice.coordinate?.latitude ?? 0
                let lon = notice.coordinate?.longitude ?? 0
                let key = "\(notice.code)|\(String(format: "%.5f", lat))|\(String(format: "%.5f", lon))"
                guard seenKeys.insert(key).inserted else { continue }
                notices.append(notice)
            }
        }

        if let warnings = trip.warnings {
            for warning in warnings {
                let text = (warning.text ?? warning.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let code = warning.code.map(String.init) ?? "valhalla_warning"
                let key = "trip|\(code)|\(text.prefix(80))"
                guard seenKeys.insert(key).inserted else { continue }
                notices.append(TruckRouteNotice(
                    code: code,
                    title: text,
                    details: text,
                    coordinate: trip.legs.first.flatMap { leg in
                        let coords = StandardPolylineDecoder.decode(leg.shape, precision: 6)
                        return coords.first
                    }
                ))
            }
        }

        return notices
    }

    private func noticeFromManeuver(
        _ maneuver: ValhallaManeuver,
        maneuverIndex: Int,
        allManeuvers: [ValhallaManeuver],
        legCoordinates: [CLLocationCoordinate2D]
    ) -> TruckRouteNotice? {
        let instruction = maneuver.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return nil }

        let parsed = Self.classifyRestriction(instruction: instruction, maneuver: maneuver)
        guard let code = parsed?.code, let title = parsed?.title else { return nil }

        return TruckRouteNotice(
            code: code,
            title: title,
            details: instruction,
            coordinate: coordinateForManeuver(
                maneuver,
                maneuverIndex: maneuverIndex,
                allManeuvers: allManeuvers,
                in: legCoordinates
            )
        )
    }

    private func coordinateForManeuver(
        _ maneuver: ValhallaManeuver,
        maneuverIndex: Int,
        allManeuvers: [ValhallaManeuver],
        in coordinates: [CLLocationCoordinate2D]
    ) -> CLLocationCoordinate2D? {
        if let idx = maneuver.beginShapeIndex, idx >= 0, idx < coordinates.count {
            return coordinates[idx]
        }
        if let endIdx = maneuver.endShapeIndex, endIdx >= 0, endIdx < coordinates.count {
            return coordinates[endIdx]
        }
        guard !coordinates.isEmpty else { return nil }
        let totalLength = allManeuvers.reduce(0.0) { $0 + max($1.length, 0) }
        guard totalLength > 0.01 else { return coordinates.first }
        let priorLength = allManeuvers.prefix(maneuverIndex).reduce(0.0) { $0 + max($1.length, 0) }
        let ratio = min(1.0, max(0.0, priorLength / totalLength))
        let estimatedIndex = min(coordinates.count - 1, Int(ratio * Double(coordinates.count - 1)))
        return coordinates[estimatedIndex]
    }

    private static func classifyRestriction(
        instruction: String,
        maneuver: ValhallaManeuver
    ) -> (code: String, title: String)? {
        let lower = instruction.lowercased()

        if maneuver.hasTimeRestrictions == true {
            return ("time_restriction", "Time-restricted road segment")
        }

        if lower.contains("height") || lower.contains("clearance") || lower.contains("low bridge") ||
            (lower.contains("bridge") && (lower.contains("limit") || lower.contains("maximum"))) {
            return ("height_limit", "Height restriction ahead")
        }
        if lower.contains("weight") || lower.contains("gross") || lower.contains("axle") {
            return ("weight_limit", "Weight restriction ahead")
        }
        if lower.contains("tunnel") {
            return ("tunnel", "Tunnel restriction ahead")
        }
        if lower.contains("hazmat") || lower.contains("hazardous") {
            return ("hazmat", "Hazmat restriction ahead")
        }
        if lower.contains("narrow") || lower.contains("width limit") {
            return ("narrow_road", "Narrow road ahead")
        }
        if maneuver.rough == true {
            return ("rough_road", "Rough pavement ahead")
        }

        return nil
    }
}

// MARK: - Valhalla Errors

enum ValhallaError: LocalizedError {
    case serverNotConfigured
    case invalidResponse
    case serverError(Int)
    case noRoute
    case emptyPolyline

    var errorDescription: String? {
        switch self {
        case .serverNotConfigured:
            return "Valhalla server URL not set in Info.plist (keys: ValhallaServerURL or ValhallaServerURLs)"
        case .invalidResponse:
            return "Invalid response from Valhalla server"
        case .serverError(let code):
            return "Valhalla server error \(code)"
        case .noRoute:
            return "Valhalla found no route"
        case .emptyPolyline:
            return "Valhalla returned empty polyline"
        }
    }
}

// MARK: - Valhalla Response Models

private struct ValhallaRouteResponse: Decodable {
    let trip: ValhallaTrip
    /// Fase 1.2: rotas alternativas (Valhalla retorna num array top-level, cada uma com seu trip).
    let alternates: [ValhallaAlternateRoute]?
}

private struct ValhallaAlternateRoute: Decodable {
    let trip: ValhallaTrip
}

private struct ValhallaTrip: Decodable {
    let summary: ValhallaSummary
    let legs: [ValhallaLeg]
    let warnings: [ValhallaTripWarning]?
}

private struct ValhallaTripWarning: Decodable {
    let code: Int?
    let text: String?
    let message: String?
}

private struct ValhallaSummary: Decodable {
    let length: Double      // miles (we asked for "units": "miles")
    let time: Double        // seconds — Valhalla 3.5+ returns fractional seconds
    let hasToll: Bool?

    enum CodingKeys: String, CodingKey {
        case length, time
        case hasToll = "has_toll"
    }
}

private struct ValhallaLeg: Decodable {
    let shape: String                   // polyline6-encoded coordinates
    let maneuvers: [ValhallaManeuver]
}

private struct ValhallaManeuver: Decodable {
    let type: Int
    let instruction: String
    let length: Double                  // miles
    let time: Double                    // seconds — fractional from Valhalla
    let hasTimeRestrictions: Bool?
    let tollBooth: Bool?
    let rough: Bool?
    let beginShapeIndex: Int?
    let endShapeIndex: Int?
    /// Placa estruturada do Valhalla — número/destino/via da saída EXATOS (não regex no texto).
    let sign: ValhallaSign?

    enum CodingKeys: String, CodingKey {
        case type, instruction, length, time, rough, sign
        case hasTimeRestrictions = "has_time_restrictions"
        case tollBooth = "toll_booth"
        case beginShapeIndex = "begin_shape_index"
        case endShapeIndex = "end_shape_index"
    }
}

/// Campo `sign` do maneuver Valhalla — dado de saída ESTRUTURADO (exit_number / exit_toward / exit_branch).
private struct ValhallaSign: Decodable {
    let exitNumber: [Element]?
    let exitBranch: [Element]?
    let exitToward: [Element]?

    struct Element: Decodable { let text: String }

    // Nomes REAIS confirmados no servidor Valhalla de produção (curl SLC→I-15): os campos terminam
    // em `_elements` — assumir "exit_number" daria nil sempre (caía no regex = não corrigia nada).
    enum CodingKeys: String, CodingKey {
        case exitNumber = "exit_number_elements"
        case exitBranch = "exit_branch_elements"
        case exitToward = "exit_toward_elements"
    }

    /// Número da saída exato (ex.: "32A"), juntando entradas consecutivas se houver.
    var exitNumberText: String? {
        guard let nums = exitNumber, !nums.isEmpty else { return nil }
        return nums.map(\.text).joined(separator: "/")
    }
    /// Destino da saída exato (ex.: "Waterbury").
    var exitTowardText: String? {
        guard let tw = exitToward, !tw.isEmpty else { return nil }
        return tw.map(\.text).joined(separator: ", ")
    }
}

// MARK: - Valhalla Maneuver Types → Human-Readable Direction

private enum ValhallaManeuverType: Int {
    case none = 0
    case start = 1
    case startRight = 2
    case startLeft = 3
    case destination = 4
    case destinationRight = 5
    case destinationLeft = 6
    case becomes = 7
    case continueAhead = 8
    case slightRight = 9
    case right = 10
    case sharpRight = 11
    case uturnRight = 12
    case uturnLeft = 13
    case sharpLeft = 14
    case left = 15
    case slightLeft = 16
    case rampStraight = 17
    case rampRight = 18
    case rampLeft = 19
    case exitRight = 20
    case exitLeft = 21
    case stayStraight = 22
    case stayRight = 23
    case stayLeft = 24
    case merge = 25
    case roundaboutEnter = 26
    case roundaboutExit = 27
    case ferryEnter = 28
    case ferryExit = 29

    /// Direction word for voice/display — used as `maneuver` field in RouteStep
    var instruction: String {
        switch self {
        case .none, .start, .startRight, .startLeft: return "Depart"
        case .destination, .destinationRight, .destinationLeft: return "Arrive at destination"
        case .becomes: return "Continue"
        case .continueAhead: return "Continue straight"
        case .slightRight: return "Bear right"
        case .right: return "Turn right"
        case .sharpRight: return "Turn sharply right"
        case .uturnRight, .uturnLeft: return "Make a U-turn"
        case .sharpLeft: return "Turn sharply left"
        case .left: return "Turn left"
        case .slightLeft: return "Bear left"
        case .rampStraight: return "Take the ramp straight"
        case .rampRight: return "Take the ramp on the right"
        case .rampLeft: return "Take the ramp on the left"
        case .exitRight: return "Take the exit on the right"
        case .exitLeft: return "Take the exit on the left"
        case .stayStraight: return "Stay straight"
        case .stayRight: return "Stay right"
        case .stayLeft: return "Stay left"
        case .merge: return "Merge"
        case .roundaboutEnter: return "Enter roundabout"
        case .roundaboutExit: return "Exit roundabout"
        case .ferryEnter: return "Take the ferry"
        case .ferryExit: return "Leave the ferry"
        }
    }
}

