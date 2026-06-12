// RoutingService.swift
// trucker easy app
//
// Infra real necessária para camião com restrições:
// - **Valhalla** (único motor integrado com costing `truck`: altura, peso, comprimento, hazmat, pedágios).
// - **OSRM / MapKit**: só geometria estilo automóvel — usados só como fallback (avisos `non_truck_routing` na rota).
// - **GPS** (Core Location): posição em tempo real — independente deste ficheiro; sem cobertura sem rede satélite/Wi‑Fi/cellular não há milagre no telefone.
//
// Deploy global: HTTPS público (ex. `backend/valhalla-production/`) + opcional LAN em `VALHALLA_SERVER_URLS` (HTTPS tentado primeiro).
// Cadeia: Valhalla (priorizado HTTPS → HTTP, ordem estável) → OSRM → MapKit → cache offline.

import Foundation
import MapKit
import CoreLocation

// MARK: - Routing Service

@MainActor
@Observable
final class RoutingService {
    static let shared = RoutingService()

    enum RoutingProvider: String {
        case valhalla = "Valhalla"
        case osrm = "OSRM"
        case mapKit = "MapKit"
        case cached = "Cached"
        case unknown = "Unknown"

        var isTruckAware: Bool {
            self == .valhalla
        }
    }

    enum RoutingAccessMode {
        /// Free tier: conventional automobile route only (MapKit), no truck restrictions.
        case automobileOnly
        /// Standard/Premium: Valhalla truck routing first, then existing fallbacks.
        case truckAware
    }

    // MARK: - State
    var isCalculating = false
    var lastError: String?
    var lastProvider: RoutingProvider = .unknown
    private(set) var recentEvents: [RoutingEvent] = []

    private let maxNetworkAttempts = 2
    private let networkSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        // `true` can stall well past `timeoutIntervalForRequest` while the OS probes dead hosts (e.g. *.local on device).
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private init() {
        // Poda única do cache de rotas legado (acumulado antes da persistência em background).
        // Roda fora da main thread; depois disso o cache se reconstrói já limitado.
        Task.detached(priority: .utility) {
            Self.pruneCacheOnLaunchIfNeeded()
        }
    }

    // MARK: - Self-hosted routing reachability
    //
    // xcconfig often uses `https:||host` because `//` starts a comment — Swift replaces `||` with `//` when reading URLs.
    /// On a physical device, hosts like `*.local`, `localhost`, and `127.*` from a Mac-only `/etc/hosts` setup are not
    /// routable. Skipping them avoids long timeouts before MapKit fallback.
    private static func shouldAttemptSelfHostedRoutingURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "||", with: "//")
        guard let url = URL(string: trimmed), let host = url.host?.lowercased(), !host.isEmpty else {
            return !trimmed.isEmpty
        }
        #if targetEnvironment(simulator)
        return true
        #else
        if host == "localhost" || host.hasPrefix("127.") || host.hasSuffix(".local") {
            return false
        }
        return true
        #endif
    }

    private static var enforceTruckSafeRouting: Bool {
        AppAccessPolicy.enforceTruckOnlyRouting
            || UserDefaults.standard.bool(forKey: "truckSafeOnlyMode")
    }

    // MARK: - Provider availability
    /// True when Valhalla is configured and at least one base URL is reachable on this runtime (not LAN-only on device).
    var isAvailable: Bool {
        guard ValhallaRoutingService.shared.isAvailable else { return false }
        return ValhallaRoutingService.shared.serverBaseURLs.contains {
            Self.shouldAttemptSelfHostedRoutingURL($0)
        }
    }

    // #region agent log
    private func agentLogRouting(
        runId: String,
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any] = [:]
    ) {
        let payload: [String: Any] = [
            "sessionId": "ff95f6",
            "runId": runId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: json, encoding: .utf8) else { return }
        line.append("\n")
        DeveloperDebugLog.appendNDJSONLine(line)
    }
    // #endregion

    // MARK: - Truck Route Request
    //
    // Returns a TruckRoute which HorizonView renders via MKPolyline.
    // Chain: Valhalla (if ValhallaServerURL) → OSRM → MapKit → Cached offline.

    func calculateTruckRoute(
        from origin: CLLocation,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        profile: TruckProfile,
        avoidTolls: Bool = false,
        accessMode: RoutingAccessMode = .truckAware
    ) async throws -> TruckRoute {
        let startedAt = Date()
        isCalculating = true
        defer { isCalculating = false }
        lastError = nil

        var failureReasons: [String] = []

        #if DEBUG
        print("[Routing] Starting route: \(origin.coordinate.latitude),\(origin.coordinate.longitude) → \(destination.latitude),\(destination.longitude)")
        #endif

        /// Records which engine produced the on-map polyline while preserving quantum flags merged in from Horizon.
        func routeTaggedWithGeometry(_ route: TruckRoute) -> TruckRoute {
            route.taggingGeometry(provider: lastProvider)
        }

        if accessMode == .automobileOnly {
            let mkRoute = try await fallbackMKDirections(
                from: origin,
                to: destination,
                destinationName: destinationName,
                avoidTolls: avoidTolls
            )
            lastProvider = .mapKit
            let tagged = addNonTruckAwareNotice(to: mkRoute, provider: "MapKit")
            cacheRoute(tagged, from: origin.coordinate, to: destination, sourceProvider: .mapKit)
            recordEvent(
                provider: .mapKit,
                stage: .fallbackUsed,
                destinationName: destinationName,
                startedAt: startedAt,
                detail: "free-tier automobile routing"
            )
            return routeTaggedWithGeometry(tagged)
        }

        // === Provider 1: Valhalla — truck-aware (height/weight/length/hazmat/tolls). HTTPS URLs tried before HTTP when listed together.
        let valhallaBases = ValhallaRoutingService.shared.prioritizedServerBaseURLs.filter {
            Self.shouldAttemptSelfHostedRoutingURL($0)
        }
        if ValhallaRoutingService.shared.isAvailable {
            if valhallaBases.isEmpty {
                #if DEBUG
                print("[Routing] Valhalla skipped — host is .local/localhost on physical device (use LAN IP or HTTPS tunnel in xcconfig).")
                #endif
                failureReasons.append("Valhalla: skipped (LAN-only host on device)")
            } else {
                let macro = LogisticsMacroRegion.regionAlongRoute(from: origin.coordinate, to: destination)
                #if DEBUG
                print("[Routing] macroRegion=\(macro.rawValue) valhallaCandidates=\(valhallaBases.count)")
                #endif
                for base in valhallaBases {
                    do {
                        let valRoute = try await ValhallaRoutingService.shared.calculateTruckRoute(
                            from: origin,
                            to: destination,
                            destinationName: destinationName,
                            profile: profile,
                            avoidTolls: avoidTolls,
                            serverBaseURL: base
                        )
                        guard Self.isRoutePlausible(origin: origin, destination: destination, route: valRoute) else {
                            failureReasons.append("Valhalla: implausible route rejected")
                            agentLogRouting(
                                runId: "baseline",
                                hypothesisId: "H8",
                                location: "RoutingService.swift:calculateTruckRoute",
                                message: "Rejected implausible Valhalla route",
                                data: [
                                    "crowMeters": Int(Self.crowDistanceMeters(from: origin, to: destination)),
                                    "routeMeters": Int(valRoute.distanceMeters),
                                    "destinationName": destinationName
                                ]
                            )
                            throw RoutingServiceError.noRoute
                        }
                        lastProvider = .valhalla
                        cacheRoute(valRoute, from: origin.coordinate, to: destination, sourceProvider: .valhalla)
                        #if DEBUG
                        print("[Routing] ✅ Valhalla OK (truck costing)")
                        #endif
                        recordEvent(
                            provider: .valhalla,
                            stage: .success,
                            destinationName: destinationName,
                            startedAt: startedAt,
                            detail: "Valhalla truck-aware route"
                        )
                        return routeTaggedWithGeometry(valRoute)
                    } catch {
                        failureReasons.append("Valhalla(\(base)): \(error.localizedDescription)")
                        #if DEBUG
                        print("[Routing] Valhalla failed for base \(base.prefix(48))…: \(error.localizedDescription)")
                        #endif
                    }
                }
            }
        }

        // Truck-safe only: never use OSRM/MapKit when Valhalla was configured but failed or timed out.
        if Self.enforceTruckSafeRouting, accessMode == .truckAware {
            throw RoutingServiceError.allProvidersFailed(failureReasons.joined(separator: " · "))
        }

        // === Provider 3: OSRM (driving profile; NOT truck-aware unless your server is) ===
        let osrmBaseForReachability = Self.osrmServerBaseURL()
        if Self.shouldAttemptSelfHostedRoutingURL(osrmBaseForReachability) {
            do {
                let osrmRoute = try await requestRouteFromOSRM(
                    from: origin, to: destination, destinationName: destinationName
                )
                guard Self.isRoutePlausible(origin: origin, destination: destination, route: osrmRoute) else {
                    failureReasons.append("OSRM: implausible route rejected")
                    agentLogRouting(
                        runId: "baseline",
                        hypothesisId: "H8",
                        location: "RoutingService.swift:calculateTruckRoute",
                        message: "Rejected implausible OSRM route",
                        data: [
                            "crowMeters": Int(Self.crowDistanceMeters(from: origin, to: destination)),
                            "routeMeters": Int(osrmRoute.distanceMeters),
                            "destinationName": destinationName
                        ]
                    )
                    throw RoutingServiceError.noRoute
                }
                lastProvider = .osrm
                var taggedRoute = osrmRoute
                taggedRoute = addNonTruckAwareNotice(to: taggedRoute, provider: "OSRM")
                cacheRoute(taggedRoute, from: origin.coordinate, to: destination, sourceProvider: .osrm)
                #if DEBUG
                print("[Routing] ✅ OSRM OK")
                #endif
                recordEvent(
                    provider: .osrm,
                    stage: .fallbackUsed,
                    destinationName: destinationName,
                    startedAt: startedAt,
                    detail: "fallback after Valhalla unavailable or failed"
                )
                return routeTaggedWithGeometry(taggedRoute)
            } catch {
                failureReasons.append("OSRM: \(error.localizedDescription)")
                #if DEBUG
                print("[Routing] OSRM failed: \(error.localizedDescription)")
                #endif
            }
        } else {
            #if DEBUG
            print("[Routing] OSRM skipped — host is .local/localhost on physical device (public demo: leave OSRM_SERVER_URL empty).")
            #endif
            failureReasons.append("OSRM: skipped (LAN-only host on device)")
        }

        // === Provider 4: MapKit (driving / automobile; toll avoidance when requested — no truck dimensions in MapKit) ===
        do {
            let mkRoute = try await fallbackMKDirections(
                from: origin, to: destination, destinationName: destinationName,
                avoidTolls: avoidTolls
            )
            guard Self.isRoutePlausible(origin: origin, destination: destination, route: mkRoute) else {
                failureReasons.append("MapKit: implausible route rejected")
                agentLogRouting(
                    runId: "baseline",
                    hypothesisId: "H8",
                    location: "RoutingService.swift:calculateTruckRoute",
                    message: "Rejected implausible MapKit route",
                    data: [
                        "crowMeters": Int(Self.crowDistanceMeters(from: origin, to: destination)),
                        "routeMeters": Int(mkRoute.distanceMeters),
                        "destinationName": destinationName
                    ]
                )
                throw RoutingServiceError.noRoute
            }
            lastProvider = .mapKit
            var taggedMk = mkRoute
            taggedMk = addNonTruckAwareNotice(to: taggedMk, provider: "MapKit")
            cacheRoute(taggedMk, from: origin.coordinate, to: destination, sourceProvider: .mapKit)
            recordEvent(
                provider: .mapKit,
                stage: .fallbackUsed,
                destinationName: destinationName,
                startedAt: startedAt,
                detail: "fallback automobile routing — truck restrictions not validated"
            )
            #if DEBUG
            print("[Routing] ✅ MapKit OK (driving; avoidTolls=\(avoidTolls))")
            #endif
            return routeTaggedWithGeometry(taggedMk)
        } catch {
            failureReasons.append("MapKit: \(error.localizedDescription)")
            #if DEBUG
            print("[Routing] MapKit failed: \(error.localizedDescription)")
            #endif
        }

        // === Fallback 5: Cached route ===
        if let cached = loadCachedRoute(origin: origin.coordinate, destination: destination) {
            #if DEBUG
            print("[Routing] ✅ Using cached offline route")
            #endif
            lastProvider = cached.geometryProvider
            recordEvent(
                provider: .cached,
                stage: .cacheHit,
                destinationName: destinationName,
                startedAt: startedAt,
                detail: "offline cache · geometry source: \(cached.geometryProvider.rawValue)"
            )
            return routeTaggedWithGeometry(cached.route)
        }

        // === Hard fail in production nav: never auto-apply straight-line emergency route ===
        #if DEBUG
        print("[Routing] ❌ ALL providers failed — refusing unsafe direct-line navigation")
        #endif
        let detail = failureReasons.joined(separator: " | ")
        lastProvider = .unknown
        lastError = detail
        recordEvent(
            provider: .unknown,
            stage: .emergencyDirect,
            destinationName: destinationName,
            startedAt: startedAt,
            detail: detail
        )
        // #region agent log
        agentLogRouting(
            runId: "baseline",
            hypothesisId: "H9",
            location: "RoutingService.swift:calculateTruckRoute",
            message: "All providers failed; route rejected for safety",
            data: [
                "destinationName": destinationName,
                "failureDetail": detail
            ]
        )
        // #endregion
        throw RoutingServiceError.allProvidersFailed(detail)
    }

    // MARK: - OSRM Fallback (NOT truck-aware)

    /// Base URL from Info.plist `OSRMServerURL` / build setting `OSRM_SERVER_URL`, or public OSRM demo.
    private static func osrmServerBaseURL() -> String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "OSRMServerURL") as? String ?? ""
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "||", with: "//")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !t.isEmpty, !t.contains("$(") else {
            return "https://router.project-osrm.org"
        }
        return t
    }

    private func requestRouteFromOSRM(
        from origin: CLLocation,
        to destination: CLLocationCoordinate2D,
        destinationName: String
    ) async throws -> TruckRoute {
        let originPart = Self.osrmCoordinateString(origin.coordinate)
        let destinationPart = Self.osrmCoordinateString(destination)
        let base = Self.osrmServerBaseURL()
        let path = "\(base)/route/v1/driving/\(originPart);\(destinationPart)"
        var components = URLComponents(string: path)
        components?.queryItems = [
            .init(name: "overview", value: "full"),
            .init(name: "geometries", value: "geojson"),
            .init(name: "steps", value: "true")
        ]
        guard let url = components?.url else { throw RoutingServiceError.invalidURL }

        let (data, response) = try await fetchDataWithRetry(from: url, provider: "OSRM")
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw RoutingServiceError.networkError("OSRM HTTP \(code)")
        }

        let decoded = try JSONDecoder().decode(OSRMRouteResponse.self, from: data)
        guard let route = decoded.routes.first else { throw RoutingServiceError.noRoute }

        let coordinates = route.geometry.coordinates.map {
            CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
        }
        let steps: [RouteStep] = route.legs.flatMap { leg in
            leg.steps.map { step in
                let maneuver = [step.maneuver.type, step.maneuver.modifier]
                    .compactMap { $0 }
                    .joined(separator: " ")
                return RouteStep(
                    instruction: step.name.isEmpty ? maneuver : step.name,
                    distanceMeters: step.distance,
                    durationSeconds: step.duration,
                    maneuver: maneuver
                )
            }
        }

        return TruckRoute(
            coordinates: coordinates,
            steps: steps,
            distanceMeters: route.distance,
            durationSeconds: route.duration,
            destinationName: destinationName,
            truckNotices: []
        )
    }

    // MARK: - Synthetic Steps Fallback (when API returns 0 maneuver steps)

    private func generateSyntheticSteps(
        from coordinates: [CLLocationCoordinate2D],
        totalDistance: Double,
        totalDuration: Double,
        destinationName: String
    ) -> [RouteStep] {
        guard coordinates.count >= 2 else {
            return [RouteStep(instruction: "Head to \(destinationName)", distanceMeters: totalDistance, durationSeconds: totalDuration, maneuver: "continue")]
        }

        var steps: [RouteStep] = []
        let segmentCount = max(1, min(coordinates.count - 1, 20)) // max 20 synthetic steps
        let sampleStride = max(1, (coordinates.count - 1) / segmentCount)
        var sampledIndexes: [Int] = Array(Swift.stride(from: 0, to: coordinates.count - 1, by: sampleStride))
        if sampledIndexes.last != coordinates.count - 1 {
            sampledIndexes.append(coordinates.count - 1)
        }

        for i in 0..<(sampledIndexes.count - 1) {
            let fromIndex = sampledIndexes[i]
            let toIndex = sampledIndexes[i + 1]
            let from = coordinates[fromIndex]
            let to = coordinates[toIndex]
            let segmentDistance = CLLocation(latitude: from.latitude, longitude: from.longitude)
                .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
            let duration = totalDistance > 0
                ? totalDuration * (segmentDistance / totalDistance)
                : 0
            let bearing = Self.bearing(from: from, to: to)
            let direction = Self.cardinalDirection(bearing)
            let roadHint = i == 0 ? "Head \(direction)" : "Continue \(direction)"
            steps.append(RouteStep(
                instruction: roadHint,
                distanceMeters: max(segmentDistance, 1),
                durationSeconds: max(duration, 0),
                maneuver: i == 0 ? "depart" : "continue"
            ))
        }

        // Final arrive step
        steps.append(RouteStep(instruction: "Arrive at \(destinationName)", distanceMeters: 0, durationSeconds: 0, maneuver: "arrive"))
        return steps
    }

    private static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let rad = atan2(y, x)
        return (rad * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func cardinalDirection(_ bearing: Double) -> String {
        switch bearing {
        case 337.5...360, 0..<22.5: return "north"
        case 22.5..<67.5: return "northeast"
        case 67.5..<112.5: return "east"
        case 112.5..<157.5: return "southeast"
        case 157.5..<202.5: return "south"
        case 202.5..<247.5: return "southwest"
        case 247.5..<292.5: return "west"
        case 292.5..<337.5: return "northwest"
        default: return "ahead"
        }
    }

    private static func isValidCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude.isFinite &&
        coordinate.longitude.isFinite &&
        abs(coordinate.latitude) <= 90 &&
        abs(coordinate.longitude) <= 180
    }

    private static func crowDistanceMeters(from origin: CLLocation, to destination: CLLocationCoordinate2D) -> Double {
        origin.distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
    }

    private static func polylineLengthMeters(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count >= 2 else { return 0 }
        var total = 0.0
        for idx in 1..<coordinates.count {
            total += CLLocation(latitude: coordinates[idx - 1].latitude, longitude: coordinates[idx - 1].longitude)
                .distance(from: CLLocation(latitude: coordinates[idx].latitude, longitude: coordinates[idx].longitude))
        }
        return total
    }

        private static func isRoutePlausible(
            origin: CLLocation,
            destination: CLLocationCoordinate2D,
            route: TruckRoute
        ) -> Bool {
            let crow = crowDistanceMeters(from: origin, to: destination)
            let routeMeters = route.distanceMeters
            let polyMeters = polylineLengthMeters(route.coordinates)

            guard routeMeters > 0, routeMeters.isFinite else { return false }
            if crow < 1_000 && routeMeters > 80_000 { return false }
            if crow < 15_000 && routeMeters > 500_000 { return false }
            if crow < 120_000 && routeMeters > 2_400_000 { return false }
            if polyMeters > 1_000 && routeMeters > polyMeters * 6 { return false }
            return true
        }

        private static func osrmCoordinateString(_ coordinate: CLLocationCoordinate2D) -> String {
            String(format: "%.6f,%.6f", coordinate.longitude, coordinate.latitude)
        }

        // MARK: - Nuclear Fallback: Direct Route (NEVER fails)

        private func generateDirectRoute(
            from origin: CLLocationCoordinate2D,
            to destination: CLLocationCoordinate2D,
            destinationName: String
        ) -> TruckRoute {
            let originLoc = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            let destLoc = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
            let distanceMeters = originLoc.distance(from: destLoc)
            let durationSeconds = distanceMeters / 22.352 // assume ~50mph average

            // Create polyline with intermediate points (great circle)
            let pointCount = max(10, Int(distanceMeters / 1000)) // 1 point per km, min 10
            var coordinates: [CLLocationCoordinate2D] = []
            for i in 0...pointCount {
                let fraction = Double(i) / Double(pointCount)
                let lat = origin.latitude + fraction * (destination.latitude - origin.latitude)
                let lon = origin.longitude + fraction * (destination.longitude - origin.longitude)
                coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }

            let steps = generateSyntheticSteps(from: coordinates, totalDistance: distanceMeters, totalDuration: durationSeconds, destinationName: destinationName)

            #if DEBUG
            print("[Routing] Direct route: \(Int(distanceMeters / 1000)) km | \(Int(durationSeconds / 60)) min | \(steps.count) steps")
            #endif
            return TruckRoute(
                coordinates: coordinates,
                steps: steps,
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                destinationName: destinationName,
                truckNotices: [TruckRouteNotice(code: "DIRECT", title: "Direct route", details: "Road data unavailable. Drive with caution.")]
            )
        }

        // MARK: - Geocode + Route (address string)

        func calculateTruckRoute(
            from origin: CLLocation,
            toAddress address: String,
            profile: TruckProfile,
            avoidTolls: Bool = false,
            accessMode: RoutingAccessMode = .truckAware
        ) async throws -> TruckRoute {
            let searchRequest = MKLocalSearch.Request()
            searchRequest.naturalLanguageQuery = address
            let search = MKLocalSearch(request: searchRequest)
            guard let result = try? await search.start(),
                  let item = result.mapItems.first else {
                throw RoutingServiceError.geocodeFailed(address)
            }

            return try await calculateTruckRoute(
                from: origin,
                to: item.placemark.coordinate,
                destinationName: item.name ?? address,
                profile: profile,
                avoidTolls: avoidTolls,
                accessMode: accessMode
            )
        }

        // MARK: - MKDirections Fallback

        /// MapKit does not model height/weight/GVW. We honour **toll avoidance** via `MKDirectionsRoutePreference` (iOS 16+).
        private func applyMapKitDrivingPreferences(_ request: MKDirections.Request, avoidTolls: Bool) {
            request.transportType = .automobile
            request.tollPreference = avoidTolls ? .avoid : .any
            request.highwayPreference = .any
        }

        private func fallbackMKDirections(
            from origin: CLLocation,
            to destination: CLLocationCoordinate2D,
            destinationName: String,
            avoidTolls: Bool = false
        ) async throws -> TruckRoute {
            let destPlacemark = MKPlacemark(coordinate: destination)
            let destItem = MKMapItem(placemark: destPlacemark)
            destItem.name = destinationName

            let originPlacemark = MKPlacemark(coordinate: origin.coordinate)
            let originItem = MKMapItem(placemark: originPlacemark)

            let request = MKDirections.Request()
            request.source = originItem
            request.destination = destItem
            applyMapKitDrivingPreferences(request, avoidTolls: avoidTolls)

            let response = try await MKDirections(request: request).calculate()
            guard let mkRoute = response.routes.first else {
                throw RoutingServiceError.noRoute
            }

            let count = mkRoute.polyline.pointCount
            var coords = [CLLocationCoordinate2D](repeating: .init(), count: count)
            mkRoute.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))

            let steps: [RouteStep] = mkRoute.steps.compactMap { step in
                guard !step.instructions.isEmpty else { return nil }
                return RouteStep(
                    instruction: step.instructions,
                    distanceMeters: step.distance,
                    durationSeconds: 0,
                    maneuver: step.instructions
                )
            }

            return TruckRoute(
                coordinates: coords,
                steps: steps,
                distanceMeters: mkRoute.distance,
                durationSeconds: mkRoute.expectedTravelTime,
                destinationName: destinationName,
                truckNotices: []
            )
        }

        /// Encadeia **MKDirections** entre coordenadas consecutivas (ex.: ordem devolvida pelo middleware de otimização).
        /// Produz um único `TruckRoute` navegável no MapKit (automobile + mesmas preferências de portagem que `fallbackMKDirections`).
        func buildTruckRouteFromMapKitDirectionsChain(
            from origin: CLLocation,
            waypointSequence: [(coordinate: CLLocationCoordinate2D, name: String)],
            avoidTolls: Bool = false
        ) async throws -> TruckRoute {
            guard !waypointSequence.isEmpty else { throw RoutingServiceError.noRoute }

            var mergedCoords: [CLLocationCoordinate2D] = []
            var mergedSteps: [RouteStep] = []
            var totalDistance: Double = 0
            var totalDuration: Double = 0
            var current = origin

            for wp in waypointSequence {
                let destPlacemark = MKPlacemark(coordinate: wp.coordinate)
                let destItem = MKMapItem(placemark: destPlacemark)
                destItem.name = wp.name

                let currentPlacemark = MKPlacemark(coordinate: current.coordinate)
                let currentItem = MKMapItem(placemark: currentPlacemark)

                let request = MKDirections.Request()
                request.source = currentItem
                request.destination = destItem
                applyMapKitDrivingPreferences(request, avoidTolls: avoidTolls)

                let response = try await MKDirections(request: request).calculate()
                guard let mkRoute = response.routes.first else { throw RoutingServiceError.noRoute }

                let count = mkRoute.polyline.pointCount
                var segCoords = [CLLocationCoordinate2D](repeating: .init(), count: count)
                mkRoute.polyline.getCoordinates(&segCoords, range: NSRange(location: 0, length: count))

                if mergedCoords.isEmpty {
                    mergedCoords.append(contentsOf: segCoords)
                } else if let first = segCoords.first, let last = mergedCoords.last, !Self.coordinatesNearlyEqual(first, last) {
                    mergedCoords.append(contentsOf: segCoords)
                } else {
                    mergedCoords.append(contentsOf: segCoords.dropFirst())
                }

                let segSteps: [RouteStep] = mkRoute.steps.compactMap { step in
                    guard !step.instructions.isEmpty else { return nil }
                    return RouteStep(
                        instruction: step.instructions,
                        distanceMeters: step.distance,
                        durationSeconds: 0,
                        maneuver: step.instructions
                    )
                }
                mergedSteps.append(contentsOf: segSteps)

                totalDistance += mkRoute.distance
                totalDuration += mkRoute.expectedTravelTime
                current = CLLocation(latitude: wp.coordinate.latitude, longitude: wp.coordinate.longitude)
            }

            let finalName = waypointSequence.last?.name ?? "Destination"
            lastProvider = .mapKit
            return TruckRoute(
                coordinates: mergedCoords,
                steps: mergedSteps,
                distanceMeters: totalDistance,
                durationSeconds: totalDuration,
                destinationName: finalName,
                truckNotices: []
            )
        }

        private static func coordinatesNearlyEqual(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
            let la = CLLocation(latitude: a.latitude, longitude: a.longitude)
            let lb = CLLocation(latitude: b.latitude, longitude: b.longitude)
            return la.distance(from: lb) < 4.0
        }

        // MARK: - Offline Route Cache (up to 10 recent routes, 7-day expiry)

        private static let maxCachedRoutes = 10
        private static let cacheExpirySeconds: TimeInterval = 7 * 24 * 3600
        private static let cacheKey = "offlineRouteCache_v3"

        private func cacheRoute(
            _ route: TruckRoute,
            from origin: CLLocationCoordinate2D,
            to destination: CLLocationCoordinate2D,
            sourceProvider: RoutingProvider
        ) {
            let payload = CachedRoutePayload(
                originLatitude: origin.latitude,
                originLongitude: origin.longitude,
                destinationLatitude: destination.latitude,
                destinationLongitude: destination.longitude,
                destinationName: route.destinationName,
                distanceMeters: route.distanceMeters,
                durationSeconds: route.durationSeconds,
                coordinates: route.coordinates.map {
                    CachedCoordinate(latitude: $0.latitude, longitude: $0.longitude)
                },
                steps: route.steps.map {
                    CachedStep(
                        instruction: $0.instruction,
                        distanceMeters: $0.distanceMeters,
                        durationSeconds: $0.durationSeconds,
                        maneuver: $0.maneuver
                    )
                },
                cachedAt: Date().timeIntervalSince1970,
                originalRoutingProvider: sourceProvider.rawValue
            )

            // Persistência pesada (JSON encode/decode de até maxCachedRoutes rotas, cada uma com
            // milhares de pontos de shape) sai da main thread — antes travava a UI ao aplicar a rota.
            Task.detached(priority: .utility) {
                Self.persistCachedRoute(payload)
            }
        }

        /// Faz load + merge + encode + save do cache FORA da main thread (chamado via `Task.detached`).
        nonisolated private static func persistCachedRoute(_ payload: CachedRoutePayload) {
            var cached = loadAllCachedRoutesStatic()

            let now = Date().timeIntervalSince1970
            cached.removeAll { now - $0.cachedAt > cacheExpirySeconds }

            let newDest = CLLocation(latitude: payload.destinationLatitude, longitude: payload.destinationLongitude)
            cached.removeAll { existing in
                let existingDest = CLLocation(latitude: existing.destinationLatitude, longitude: existing.destinationLongitude)
                return existingDest.distance(from: newDest) < 5_000
            }

            cached.insert(payload, at: 0)

            if cached.count > maxCachedRoutes {
                cached = Array(cached.prefix(maxCachedRoutes))
            }

            guard let data = try? JSONEncoder().encode(cached) else { return }
            UserDefaults.standard.set(data, forKey: cacheKey)
            #if DEBUG
            print("[Routing] ✅ Cached route to '\(payload.destinationName)' (\(cached.count) routes stored)")
            #endif
        }

        private func loadAllCachedRoutes() -> [CachedRoutePayload] {
            Self.loadAllCachedRoutesStatic()
        }

        /// Limpa, UMA única vez, o cache de rotas legado (potencialmente grande) que foi gravado
        /// antes da persistência em segundo plano. Ele se reconstrói nos próximos cálculos.
        nonisolated private static func pruneCacheOnLaunchIfNeeded() {
            let flagKey = "offlineRouteCachePrunedV4"
            let defaults = UserDefaults.standard
            guard !defaults.bool(forKey: flagKey) else { return }
            defaults.removeObject(forKey: cacheKey)
            defaults.removeObject(forKey: "lastOfflineRoute")
            defaults.set(true, forKey: flagKey)
            #if DEBUG
            print("[Routing] 🧹 Cache de rotas legado limpo (poda única)")
            #endif
        }

        nonisolated private static func loadAllCachedRoutesStatic() -> [CachedRoutePayload] {
            guard let data = UserDefaults.standard.data(forKey: cacheKey),
                  let routes = try? JSONDecoder().decode([CachedRoutePayload].self, from: data) else {
                if let oldData = UserDefaults.standard.data(forKey: "lastOfflineRoute"),
                   let old = try? JSONDecoder().decode(CachedRoutePayload.self, from: oldData) {
                    UserDefaults.standard.removeObject(forKey: "lastOfflineRoute")
                    return [old]
                }
                return []
            }
            return routes
        }

        private struct LoadedCachedRoute {
            let route: TruckRoute
            /// Provider that originally computed the geometry (`.cached` if legacy payload had no provenance).
            let geometryProvider: RoutingProvider
        }

        private func loadCachedRoute(origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D) -> LoadedCachedRoute? {
            let cached = loadAllCachedRoutes()
            let currentOrigin = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            let currentDestination = CLLocation(latitude: destination.latitude, longitude: destination.longitude)

            let match = cached.first { payload in
                let cachedOrigin = CLLocation(latitude: payload.originLatitude, longitude: payload.originLongitude)
                let cachedDestination = CLLocation(latitude: payload.destinationLatitude, longitude: payload.destinationLongitude)
                let originDist = currentOrigin.distance(from: cachedOrigin)
                let destDist = currentDestination.distance(from: cachedDestination)
                let age = Date().timeIntervalSince1970 - payload.cachedAt
                return originDist < 3_000 && destDist < 3_000 && age < Self.cacheExpirySeconds
            }

            guard let payload = match else { return nil }

            let geometryProvider: RoutingProvider = {
                guard let raw = payload.originalRoutingProvider,
                      let p = RoutingProvider(rawValue: raw),
                      p != .cached, p != .unknown
                else { return .cached }
                return p
            }()

            let route = TruckRoute(
                coordinates: payload.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) },
                steps: payload.steps.map {
                    RouteStep(
                        instruction: $0.instruction,
                        distanceMeters: $0.distanceMeters,
                        durationSeconds: $0.durationSeconds,
                        maneuver: $0.maneuver
                    )
                },
                distanceMeters: payload.distanceMeters,
                durationSeconds: payload.durationSeconds,
                destinationName: payload.destinationName,
                truckNotices: []
            )
            return LoadedCachedRoute(route: route, geometryProvider: geometryProvider)
        }

        private func fetchDataWithRetry(
            from url: URL,
            provider: String
        ) async throws -> (Data, URLResponse) {
            var lastThrownError: Error?

            for attempt in 1...maxNetworkAttempts {
                do {
                    let result = try await networkSession.data(from: url)
                    if let http = result.1 as? HTTPURLResponse, (500...599).contains(http.statusCode), attempt < maxNetworkAttempts {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        continue
                    }
                    return result
                } catch {
                    lastThrownError = error
                    if attempt < maxNetworkAttempts {
                        #if DEBUG
                        print("[Routing] \(provider) attempt \(attempt) failed: \(error.localizedDescription). Retrying...")
                        #endif
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        continue
                    }
                }
            }

            throw lastThrownError ?? RoutingServiceError.networkError("\(provider) request failed")
        }

        private func addNonTruckAwareNotice(to route: TruckRoute, provider: String) -> TruckRoute {
            var r = route
            r.truckNotices.append(TruckRouteNotice(
                code: "non_truck_routing",
                title: "Car-grade route — not truck-legal verified",
                details: "Provider: \(provider). This path does not enforce bridge height, GVW/axle limits, length, tunnel clearance, or hazmat exclusions. Use only when truck-aware Valhalla is unavailable; verify signage and regulations."
            ))
            return r
        }

        private func recordEvent(
            provider: RoutingProvider,
            stage: RoutingStage,
            destinationName: String,
            startedAt: Date,
        detail: String
    ) {
        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let event = RoutingEvent(
            timestamp: Date(),
            provider: provider.rawValue,
            stage: stage.rawValue,
            destinationName: destinationName,
            elapsedMs: elapsedMs,
            detail: detail
        )
        recentEvents.insert(event, at: 0)
        if recentEvents.count > 50 {
            recentEvents = Array(recentEvents.prefix(50))
        }
        if let data = try? JSONEncoder().encode(recentEvents) {
            UserDefaults.standard.set(data, forKey: "routing_events_v1")
        }
        #if DEBUG
        print("[Routing][\(stage.rawValue)] provider=\(provider.rawValue) elapsed=\(elapsedMs)ms dest='\(destinationName)' detail='\(detail)'")
        #endif
    }

    enum RoutingStage: String, Codable {
        case success
        case fallbackUsed
        case cacheHit
        case emergencyDirect
        case invalidInput
    }
}

struct RoutingEvent: Codable, Equatable {
    let timestamp: Date
    let provider: String
    let stage: String
    let destinationName: String
    let elapsedMs: Int
    let detail: String
}

// MARK: - TruckRoute Model

struct TruckRoute: Equatable {
    let coordinates: [CLLocationCoordinate2D]
    let steps: [RouteStep]
    let distanceMeters: Double
    let durationSeconds: Double
    let destinationName: String
    var truckNotices: [TruckRouteNotice]

    /// Geometry source + optional quantum **stop-order** metadata from `POST /v1/optimize`.
    var provenance: TruckRouteProvenance? = nil

    // Toll data — populated from routing response
    var tollCostUSD: Double = 0
    var tollCurrency: String = "USD"
    var tollPoints: [TollPoint] = []

    var polyline: MKPolyline {
        MKPolyline(coordinates: coordinates, count: coordinates.count)
    }

    var hasTruckRestrictions: Bool { !truckNotices.isEmpty }
    var hasTollData: Bool { tollCostUSD > 0.01 || !tollPoints.isEmpty }

    static func == (lhs: TruckRoute, rhs: TruckRoute) -> Bool {
        lhs.distanceMeters == rhs.distanceMeters &&
        lhs.durationSeconds == rhs.durationSeconds &&
        lhs.destinationName == rhs.destinationName &&
        lhs.provenance == rhs.provenance
    }
}

extension TruckRoute {
    var distanceMiles: Double { distanceMeters / 1609.34 }
    var distanceKm: Double { distanceMeters / 1000.0 }
    var durationHours: Double { durationSeconds / 3600.0 }
}

struct RouteStep: Equatable {
    let instruction: String
    let distanceMeters: Double
    let durationSeconds: Double
    let maneuver: String
}

struct TruckRouteNotice: Equatable {
    let code: String
    let title: String
    let details: String?
    /// Map position along the route (Valhalla `begin_shape_index` → polyline point).
    var coordinate: CLLocationCoordinate2D? = nil

    static func == (lhs: TruckRouteNotice, rhs: TruckRouteNotice) -> Bool {
        lhs.code == rhs.code &&
        lhs.title == rhs.title &&
        lhs.details == rhs.details &&
        lhs.coordinate?.latitude == rhs.coordinate?.latitude &&
        lhs.coordinate?.longitude == rhs.coordinate?.longitude
    }
}

// MARK: - Routing Errors

enum RoutingServiceError: LocalizedError {
    case invalidURL
    case networkError(String)
    case unauthorized
    case serverError(Int, String)
    case noRoute
    case allProvidersFailed(String)
    case geocodeFailed(String)
    case emptyPolyline

    var errorDescription: String? {
        switch self {
        case .invalidURL:                    return "Invalid routing URL"
        case .networkError(let msg):         return "Network error: \(msg)"
        case .unauthorized:                  return "API key is invalid or expired"
        case .serverError(let c, _):         return "Server error \(c)"
        case .noRoute:                       return "No route found"
        case .allProvidersFailed(let detail): return "Route unavailable (\(detail))"
        case .geocodeFailed(let addr):       return "Could not find address: \(addr)"
        case .emptyPolyline:                 return "Route polyline is empty"
        }
    }
}

// MARK: - Toll Models

struct TollResult: Equatable {
    let totalCost: Double
    let currency: String
    let tolls: [TollPoint]

    var hasTolls: Bool { totalCost > 0.01 }

    var formattedTotal: String {
        guard hasTolls else { return "No Tolls" }
        let symbol = currencySymbol(for: currency)
        return String(format: "%@%.2f", symbol, totalCost)
    }

    var formattedShort: String {
        guard hasTolls else { return "$0" }
        let symbol = currencySymbol(for: currency)
        if totalCost < 10 {
            return String(format: "%@%.2f", symbol, totalCost)
        }
        return String(format: "%@%.0f", symbol, totalCost)
    }

    private func currencySymbol(for code: String) -> String {
        switch code.uppercased() {
        case "USD": return "$"
        case "CAD": return "C$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "BRL": return "R$"
        case "MXN": return "MX$"
        default:    return code + " "
        }
    }

    static let zero = TollResult(totalCost: 0, currency: "USD", tolls: [])

    init(totalCost: Double, currency: String, tolls: [TollPoint]) {
        self.totalCost = totalCost
        self.currency  = currency
        self.tolls     = tolls
    }
}

struct TollPoint: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let cost: Double
    let coordinate: CLLocationCoordinate2D?

    static func == (lhs: TollPoint, rhs: TollPoint) -> Bool {
        lhs.id == rhs.id
    }

    init(name: String, cost: Double, coordinate: CLLocationCoordinate2D?) {
        self.name = name
        self.cost = cost
        self.coordinate = coordinate
    }
}

// MARK: - Trip Profitability Calculator

struct TripProfitability {
    let freightValueUSD: Double
    let estimatedFuelCostUSD: Double
    let tollCostUSD: Double
    let otherExpensesUSD: Double

    var netProfitUSD: Double {
        freightValueUSD - estimatedFuelCostUSD - tollCostUSD - otherExpensesUSD
    }

    var profitMarginPct: Double {
        guard freightValueUSD > 0 else { return 0 }
        return (netProfitUSD / freightValueUSD) * 100
    }

    var revenuePerMile: Double { 0 }

    static func estimateFuelCost(distanceMeters: Double, mpg: Double = 6.5, dieselPricePerGallon: Double = 3.80) -> Double {
        let miles = distanceMeters / 1609.34
        let gallons = miles / mpg
        return gallons * dieselPricePerGallon
    }

    var formatted: ProfitFormatted {
        ProfitFormatted(
            freight:   format(freightValueUSD),
            fuel:      format(estimatedFuelCostUSD),
            tolls:     format(tollCostUSD),
            expenses:  format(otherExpensesUSD),
            net:       format(netProfitUSD),
            margin:    String(format: "%.0f%%", profitMarginPct),
            isProfit:  netProfitUSD >= 0
        )
    }

    private func format(_ value: Double) -> String {
        if value == 0 { return "$0" }
        return String(format: "$%.2f", abs(value))
    }

    struct ProfitFormatted {
        let freight: String
        let fuel: String
        let tolls: String
        let expenses: String
        let net: String
        let margin: String
        let isProfit: Bool
    }
}

// MARK: - Standard Polyline Decoder (Google format, precision 5 or 6)

enum StandardPolylineDecoder {
    static func decode(_ encoded: String, precision: Int = 6) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        var index = encoded.startIndex
        let end = encoded.endIndex
        let factor = pow(10.0, Double(precision))

        var lat = 0
        var lng = 0

        while index < end {
            var result = 0
            var shift = 0
            var b: Int

            repeat {
                guard index < end else { return coordinates }
                b = Int(encoded[index].asciiValue ?? 63) - 63
                index = encoded.index(after: index)
                result += (b & 0x1F) << shift
                shift += 5
            } while b >= 0x20

            let dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lat += dlat

            result = 0
            shift = 0

            repeat {
                guard index < end else { return coordinates }
                b = Int(encoded[index].asciiValue ?? 63) - 63
                index = encoded.index(after: index)
                result += (b & 0x1F) << shift
                shift += 5
            } while b >= 0x20

            let dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lng += dlng

            coordinates.append(CLLocationCoordinate2D(
                latitude:  Double(lat) / factor,
                longitude: Double(lng) / factor
            ))
        }

        return coordinates
    }
}

// MARK: - Private Response Models

private struct OSRMRouteResponse: Decodable {
    let routes: [Route]

    struct Route: Decodable {
        let distance: Double
        let duration: Double
        let geometry: Geometry
        let legs: [Leg]
    }

    struct Geometry: Decodable {
        let coordinates: [[Double]]
    }

    struct Leg: Decodable {
        let steps: [Step]
    }

    struct Step: Decodable {
        let distance: Double
        let duration: Double
        let name: String
        let maneuver: Maneuver
    }

    struct Maneuver: Decodable {
        let type: String
        let modifier: String?
    }
}

private struct CachedRoutePayload: Codable, Sendable {
    let originLatitude: Double
    let originLongitude: Double
    let destinationLatitude: Double
    let destinationLongitude: Double
    let destinationName: String
    let distanceMeters: Double
    let durationSeconds: Double
    let coordinates: [CachedCoordinate]
    let steps: [CachedStep]
    let cachedAt: TimeInterval
    /// Raw value of `RoutingProvider` when the route was first stored (`Valhalla` / `OSRM` / `MapKit`). Absent in legacy cache JSON.
    let originalRoutingProvider: String?
}

private struct CachedCoordinate: Codable {
    let latitude: Double
    let longitude: Double
}

private struct CachedStep: Codable {
    let instruction: String
    let distanceMeters: Double
    let durationSeconds: Double
    let maneuver: String
}
