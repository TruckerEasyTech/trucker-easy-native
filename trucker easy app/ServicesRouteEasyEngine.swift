// ServicesRouteEasyEngine.swift
// Route Easy — compara rotas camião (rápida vs sem pedágio vs inteligência operacional).

import CoreLocation
import Foundation

enum RouteEasyKind: String, CaseIterable, Identifiable, Hashable {
    case fastest
    case fewerTolls
    case fuelSmart

    var id: String { rawValue }
}

struct RouteEasyOption: Identifiable {
    let kind: RouteEasyKind
    let route: TruckRoute
    let provider: RoutingService.RoutingProvider
    let durationSeconds: Double
    let distanceMeters: Double
    let tollUSD: Double
    let fuelUSD: Double
    /// Poupança estimada vs diesel de referência ao abastecer no posto sugerido.
    let fuelSavingsUSD: Double?
    let fuelStopName: String?
    let subtitle: String
    let decisionSummary: String?
    let estimatedSavingsUSD: Double?
    let recommendedStopsCount: Int
    /// true = esta rota paga é IDÊNTICA à Free (mesma distância/tempo/pedágio) → o card NÃO mostra os
    /// números repetidos (milhas/pedágio/diesel), só o valor do plano. Justifica o preço sem parecer clone.
    var matchesFastest: Bool = false

    var id: String { kind.rawValue }

    var requiredPlan: TruckerEasyPlan { AppAccessPolicy.requiredPlan(for: kind) }

    func isAccessible(for plan: TruckerEasyPlan) -> Bool {
        AppAccessPolicy.canUseRouteEasyKind(kind, plan: plan)
    }

    var durationMinutes: Int { max(1, Int(durationSeconds / 60)) }
    var estimatedTotalUSD: Double { max(0, tollUSD) + max(0, fuelUSD) }
}

@MainActor
enum RouteEasyEngine {

    /// Builds all three Route Easy cards — free route + locked previews for Standard/Premium upsell.
    static func buildOptions(
        from origin: CLLocation,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        profile: TruckProfile,
        dieselPricePerGallon: Double,
        mpg: Double,
        nearbyFuelStops: [TruckStopItem] = [],
        effectivePlan: TruckerEasyPlan,
        includeFuelSmart: Bool = true,
        prefetchedFastest: TruckRoute? = nil,
        prefetchedFastProvider: RoutingService.RoutingProvider? = nil
    ) async throws -> [RouteEasyOption] {
        let routing = RoutingService.shared
        let usesTruckForFreeTier = effectivePlan.hasTruckRoutes || AppAccessPolicy.unlockAllFeaturesForTesting
        let freeAccess: RoutingService.RoutingAccessMode = usesTruckForFreeTier ? .truckAware : .automobileOnly

        let fastRoute: TruckRoute
        let fastProvider: RoutingService.RoutingProvider
        if let prefetchedFastest, let prefetchedFastProvider {
            fastRoute = prefetchedFastest
            fastProvider = prefetchedFastProvider
        } else {
            fastRoute = try await routing.calculateTruckRoute(
                from: origin,
                to: destination,
                destinationName: destinationName,
                profile: profile,
                avoidTolls: false,
                accessMode: freeAccess
            )
            fastProvider = routing.lastProvider
        }

        // Second Valhalla call is optional — cap wait so the driver is not stuck after the fastest route succeeds.
        var tollRoute: TruckRoute?
        var tollProvider = fastProvider
        if let toll = await fetchAvoidTollsPreview(
            routing: routing,
            origin: origin,
            destination: destination,
            destinationName: destinationName,
            profile: profile,
            timeoutSeconds: 10
        ) {
            tollRoute = toll.route
            tollProvider = toll.provider
        }

        var options: [RouteEasyOption] = []
        let freeSubtitle = usesTruckForFreeTier
            ? "Truck-safe · \(fastProvider.rawValue)"
            : "Free · Apple Maps driving route"

        options.append(
            makeOption(
                kind: .fastest,
                route: fastRoute,
                provider: fastProvider,
                dieselPrice: dieselPricePerGallon,
                mpg: mpg,
                fuelStop: nil,
                compareTo: nil,
                decisionSummary: usesTruckForFreeTier
                    ? "Fastest route your plan includes."
                    : "Included on Free. Upgrade for truck height, weight, and hazmat routing.",
                subtitleOverride: freeSubtitle
            )
        )

        let noTollRoute = tollRoute ?? fastRoute
        options.append(
            makeOption(
                kind: .fewerTolls,
                route: noTollRoute,
                provider: tollRoute == nil ? fastProvider : tollProvider,
                dieselPrice: dieselPricePerGallon,
                mpg: mpg,
                fuelStop: nil,
                compareTo: fastRoute,
                decisionSummary: tollRoute != nil
                    ? "Avoids or minimizes toll roads when the truck-safe engine can do it."
                    : "Standard plan unlocks truck-safe routes that skip tolls when possible.",
                estimatedSavingsUSD: max(0, fastRoute.tollCostUSD - noTollRoute.tollCostUSD),
                recommendedStopsCount: 0,
                subtitleOverride: tollRoute == nil ? "Standard · truck route without tolls" : nil
            )
        )

        if includeFuelSmart {
            if let smart = aiSmartOption(
                fastRoute: fastRoute,
                fastProvider: fastProvider,
                noTollRoute: noTollRoute,
                noTollProvider: tollRoute == nil ? fastProvider : tollProvider,
                dieselPrice: dieselPricePerGallon,
                mpg: mpg,
                nearbyFuelStops: nearbyFuelStops,
                compareTo: fastRoute
            ) {
                options.append(smart)
            } else {
                // Sem preço de diesel de referência (aiSmartOption exige dieselPrice > 0):
                // card honesto sem números fabricados.
                options.append(
                    makeOption(
                        kind: .fuelSmart,
                        route: noTollRoute,
                        provider: tollRoute == nil ? fastProvider : tollProvider,
                        dieselPrice: dieselPricePerGallon,
                        mpg: mpg,
                        fuelStop: nil,
                        compareTo: fastRoute,
                        decisionSummary: "Cost-optimized: compares tolls, diesel price, and driver time to pick the lowest total operating cost.",
                        estimatedSavingsUSD: nil,
                        recommendedStopsCount: 0,
                        subtitleOverride: "Premium · Cost-optimized route"
                    )
                )
            }
        }

        return ensureThreeOptions(options)
    }

    /// Builds the Free/fastest card from an already-fetched Valhalla route (instant apply on map).
    static func fastestOption(
        route: TruckRoute,
        provider: RoutingService.RoutingProvider,
        dieselPricePerGallon: Double,
        mpg: Double,
        usesTruckForFreeTier: Bool
    ) -> RouteEasyOption {
        let subtitle = usesTruckForFreeTier
            ? "Truck-safe · \(provider.rawValue)"
            : "Free · Apple Maps driving route"
        return makeOption(
            kind: .fastest,
            route: route,
            provider: provider,
            dieselPrice: dieselPricePerGallon,
            mpg: mpg,
            fuelStop: nil,
            compareTo: nil,
            decisionSummary: usesTruckForFreeTier
                ? "Fastest route your plan includes."
                : "Included on Free. Upgrade for truck height, weight, and hazmat routing.",
            subtitleOverride: subtitle
        )
    }

    private struct TollPreviewResult {
        let route: TruckRoute
        let provider: RoutingService.RoutingProvider
    }

    /// Avoid-tolls Valhalla preview with a hard timeout — never block the fastest route after it succeeds.
    private static func fetchAvoidTollsPreview(
        routing: RoutingService,
        origin: CLLocation,
        destination: CLLocationCoordinate2D,
        destinationName: String,
        profile: TruckProfile,
        timeoutSeconds: TimeInterval
    ) async -> TollPreviewResult? {
        await withTaskGroup(of: TollPreviewResult?.self) { group in
            group.addTask { @MainActor in
                do {
                    let toll = try await routing.calculateTruckRoute(
                        from: origin,
                        to: destination,
                        destinationName: destinationName,
                        profile: profile,
                        avoidTolls: true,
                        accessMode: .truckAware
                    )
                    return TollPreviewResult(route: toll, provider: routing.lastProvider)
                } catch {
                    #if DEBUG
                    print("[RouteEasy] avoid-tolls preview failed: \(error.localizedDescription)")
                    #endif
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                #if DEBUG
                print("[RouteEasy] avoid-tolls preview timed out after \(Int(timeoutSeconds))s — using fastest route only")
                #endif
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? nil
        }
    }

    private static func ensureThreeOptions(_ options: [RouteEasyOption]) -> [RouteEasyOption] {
        guard let base = options.first(where: { $0.kind == .fastest }) ?? options.first else {
            return options
        }
        return RouteEasyKind.allCases.map { kind in
            options.first(where: { $0.kind == kind }) ?? base.withKind(kind)
        }
    }

    private static func routesAreMeaningfullyDifferent(_ a: TruckRoute, _ b: TruckRoute) -> Bool {
        let distDiff = abs(a.distanceMeters - b.distanceMeters)
        let timeDiff = abs(a.durationSeconds - b.durationSeconds)
        let tollDiff = abs(a.tollCostUSD - b.tollCostUSD)
        return distDiff > 400 || timeDiff > 90 || tollDiff > 4
    }

    private static func makeOption(
        kind: RouteEasyKind,
        route: TruckRoute,
        provider: RoutingService.RoutingProvider,
        dieselPrice: Double,
        mpg: Double,
        fuelStop: TruckStopItem?,
        compareTo: TruckRoute?,
        decisionSummary: String? = nil,
        estimatedSavingsUSD: Double? = nil,
        recommendedStopsCount: Int = 0,
        subtitleOverride: String? = nil
    ) -> RouteEasyOption {
        let fuelUSD = TripProfitability.estimateFuelCost(
            distanceMeters: route.distanceMeters,
            mpg: mpg,
            dieselPricePerGallon: dieselPrice
        )
        var savings: Double?
        var stopName: String?
        if let fuelStop, let stopPrice = fuelStop.amenities.dieselPrice, stopPrice < dieselPrice - 0.02 {
            let gallons = (route.distanceMeters / 1609.34) / max(mpg, 0.1)
            savings = (dieselPrice - stopPrice) * gallons
            stopName = fuelStop.name
        }

        let subtitle: String
        if let subtitleOverride {
            subtitle = subtitleOverride
        } else {
            switch kind {
            case .fastest:
                if let compareTo, route.durationSeconds < compareTo.durationSeconds - 60 {
                    let min = Int((compareTo.durationSeconds - route.durationSeconds) / 60)
                    subtitle = "~\(min) min faster"
                } else if route.tollCostUSD > 0.01 {
                    subtitle = "Est. tolls $\(String(format: "%.0f", route.tollCostUSD))"
                } else {
                    subtitle = "Truck-safe · \(provider.rawValue)"
                }
            case .fewerTolls:
                if let compareTo {
                    let saved = compareTo.tollCostUSD - route.tollCostUSD
                    if saved > 1 {
                        subtitle = "Save ~$\(String(format: "%.0f", saved)) tolls"
                    } else if !routesAreMeaningfullyDifferent(compareTo, route) {
                        subtitle = "Avoid tolls when possible"
                    } else if route.durationSeconds > compareTo.durationSeconds + 60 {
                        let extra = Int((route.durationSeconds - compareTo.durationSeconds) / 60)
                        subtitle = "+\(extra) min · fewer tolls"
                    } else {
                        subtitle = "Lower toll estimate"
                    }
                } else {
                    subtitle = "Avoid toll preference"
                }
            case .fuelSmart:
                if let estimatedSavingsUSD, estimatedSavingsUSD > 2, let stopName {
                    subtitle = "Best cost-benefit · fuel at \(stopName) saves ~$\(String(format: "%.0f", estimatedSavingsUSD))"
                } else if let savings, savings > 2, let stopName {
                    subtitle = "Easy · stop at \(stopName) saves ~$\(String(format: "%.0f", savings))"
                } else if let stopName {
                    subtitle = "Easy · fuel/rest option: \(stopName)"
                } else {
                    subtitle = "Easy · balances time, tolls, fuel and HOS"
                }
            }
        }

        // Rota paga IDÊNTICA à Free? (mesma dist/tempo/pedágio) → o card esconde os números repetidos.
        let matchesFastest: Bool = {
            guard kind != .fastest, let compareTo else { return false }
            return !routesAreMeaningfullyDifferent(compareTo, route)
                && abs(compareTo.tollCostUSD - route.tollCostUSD) < 1
                && (estimatedSavingsUSD ?? 0) < 1
                && recommendedStopsCount == 0
        }()

        return RouteEasyOption(
            kind: kind,
            route: route,
            provider: provider,
            durationSeconds: route.durationSeconds,
            distanceMeters: route.distanceMeters,
            tollUSD: route.tollCostUSD,
            fuelUSD: fuelUSD,
            fuelSavingsUSD: savings,
            fuelStopName: stopName,
            subtitle: subtitle,
            decisionSummary: decisionSummary,
            estimatedSavingsUSD: estimatedSavingsUSD,
            recommendedStopsCount: recommendedStopsCount,
            matchesFastest: matchesFastest
        )
    }

    /// Rota inteligente por CUSTO TOTAL DE OPERAÇÃO real, por candidata:
    ///   total(candidata) = pedágio + diesel(distância ÷ MPG × preço) + tempo do motorista
    ///                      − economia abastecendo no posto mais barato NO CORREDOR DAQUELA rota.
    /// O posto é buscado no corredor de CADA candidata separadamente — o posto barato da rota
    /// rápida pode nem existir na rota sem pedágio (estradas diferentes). A escolha da rota já
    /// considera a economia do posto (antes a economia era somada DEPOIS da escolha — se o posto
    /// barato só existia numa candidata, a comparação ignorava isso).
    /// Nada fabricado: sem preço de posto real no corredor → candidata compete sem essa economia.
    private static func aiSmartOption(
        fastRoute: TruckRoute,
        fastProvider: RoutingService.RoutingProvider,
        noTollRoute: TruckRoute,
        noTollProvider: RoutingService.RoutingProvider,
        dieselPrice: Double,
        mpg: Double,
        nearbyFuelStops: [TruckStopItem],
        compareTo: TruckRoute
    ) -> RouteEasyOption? {
        guard dieselPrice > 0 else { return nil }

        // Posto mais barato no corredor de CADA candidata (8 km ≈ 5 mi; até 80% da rota,
        // para não recomendar parada colada no destino).
        let fastStop = cheapestFuelStopInCorridor(
            stops: nearbyFuelStops, routeCoords: fastRoute.coordinates,
            corridorMeters: 8_000, maxFractionAlongRoute: 0.80
        )
        let noTollStop = (noTollRoute == fastRoute) ? fastStop : cheapestFuelStopInCorridor(
            stops: nearbyFuelStops, routeCoords: noTollRoute.coordinates,
            corridorMeters: 8_000, maxFractionAlongRoute: 0.80
        )

        // Economia REAL abastecendo no posto do corredor (só se o preço do posto < referência − 2¢).
        func stopSavings(_ stop: TruckStopItem?, route: TruckRoute) -> Double {
            guard let stop, let p = stop.amenities.dieselPrice, p < dieselPrice - 0.02 else { return 0 }
            let gallons = (route.distanceMeters / 1609.34) / max(mpg, 0.1)
            return (dieselPrice - p) * gallons
        }
        func routeCost(_ route: TruckRoute, stop: TruckStopItem?) -> Double {
            let fuel = TripProfitability.estimateFuelCost(
                distanceMeters: route.distanceMeters, mpg: mpg, dieselPricePerGallon: dieselPrice)
            return max(0, route.tollCostUSD) + fuel - stopSavings(stop, route: route)
        }

        // Tempo do motorista: $0.75/min (~$45/h) sobre o tempo EXTRA vs a mais rápida.
        let fastTotal = routeCost(fastRoute, stop: fastStop)
        let extraMinutes = max(0, (noTollRoute.durationSeconds - fastRoute.durationSeconds) / 60.0)
        let noTollTotal = routeCost(noTollRoute, stop: noTollStop) + extraMinutes * 0.75

        // Sem-pedágio só vence com vantagem REAL (> $5) — empate técnico fica com a mais rápida.
        let useNoToll = noTollTotal + 5 < fastTotal
        let selectedRoute = useNoToll ? noTollRoute : fastRoute
        let selectedProvider = useNoToll ? noTollProvider : fastProvider
        let selectedStop = useNoToll ? noTollStop : fastStop
        let selectedStopSavings = stopSavings(selectedStop, route: selectedRoute)

        // Economia total vs baseline honesto: rota rápida abastecendo a preço de referência.
        let baseline = max(0, fastRoute.tollCostUSD) + TripProfitability.estimateFuelCost(
            distanceMeters: fastRoute.distanceMeters, mpg: mpg, dieselPricePerGallon: dieselPrice)
        let chosenTotal = useNoToll ? noTollTotal : fastTotal
        let savings = max(0, baseline - chosenTotal)

        var summary = useNoToll
            ? String(format: "No-toll base wins on total cost: $%.0f vs $%.0f for the fastest (tolls + fuel + %d min extra).",
                     noTollTotal, fastTotal, Int(extraMinutes))
            : "Fastest truck-safe base already has the lowest total operating cost."
        if let stop = selectedStop, let p = stop.amenities.dieselPrice, selectedStopSavings > 1 {
            summary += String(format: " Fuel at %@ ($%.2f/gal vs $%.2f avg) saves ~$%.0f.",
                              stop.name, p, dieselPrice, selectedStopSavings)
        }

        return makeOption(
            kind: .fuelSmart,
            route: selectedRoute,
            provider: selectedProvider,
            dieselPrice: dieselPrice,
            mpg: mpg,
            fuelStop: selectedStop,
            compareTo: compareTo,
            decisionSummary: summary,
            estimatedSavingsUSD: savings > 1 ? savings : nil,
            recommendedStopsCount: selectedStop == nil ? 0 : 1
        )
    }

    /// Posto de diesel mais barato DENTRO DO CORREDOR da rota — projeção ponto-segmento
    /// (equirretangular local) contra a polilinha. `maxFractionAlongRoute` evita recomendar
    /// parada já perto do destino. Retorna nil quando nenhum posto com preço REAL qualifica.
    static func cheapestFuelStopInCorridor(
        stops: [TruckStopItem],
        routeCoords: [CLLocationCoordinate2D],
        corridorMeters: Double,
        maxFractionAlongRoute: Double
    ) -> TruckStopItem? {
        guard routeCoords.count >= 2 else { return nil }
        let n = routeCoords.count

        var totalLength = 0.0
        var segLengths = [Double]()
        segLengths.reserveCapacity(n - 1)
        for i in 0..<(n - 1) {
            let d = CLLocation(latitude: routeCoords[i].latitude, longitude: routeCoords[i].longitude)
                .distance(from: CLLocation(latitude: routeCoords[i+1].latitude, longitude: routeCoords[i+1].longitude))
            segLengths.append(d)
            totalLength += d
        }
        let maxDistAlongRoute = totalLength * maxFractionAlongRoute

        var best: TruckStopItem?
        var bestPrice = Double.infinity

        for stop in stops {
            guard let price = stop.amenities.dieselPrice, price < bestPrice else { continue }
            let pt = stop.coordinate
            var minDist = Double.infinity
            var distAlongRoute = 0.0
            var closestFraction = 0.0

            for i in 0..<(n - 1) {
                let a = routeCoords[i], b = routeCoords[i+1]
                let ax = a.longitude, ay = a.latitude, bx = b.longitude, by = b.latitude
                let dx = bx - ax, dy = by - ay
                let len2 = dx*dx + dy*dy
                var t = len2 > 0 ? ((pt.longitude - ax)*dx + (pt.latitude - ay)*dy) / len2 : 0
                t = max(0, min(1, t))
                let px = ax + t*dx, py = ay + t*dy
                let d = CLLocation(latitude: pt.latitude, longitude: pt.longitude)
                    .distance(from: CLLocation(latitude: py, longitude: px))
                if d < minDist {
                    minDist = d
                    closestFraction = distAlongRoute + t * segLengths[i]
                }
                distAlongRoute += segLengths[i]
            }

            guard minDist <= corridorMeters, closestFraction <= maxDistAlongRoute else { continue }
            best = stop
            bestPrice = price
        }
        return best
    }
}

private extension RouteEasyOption {
    func withKind(_ kind: RouteEasyKind) -> RouteEasyOption {
        RouteEasyOption(
            kind: kind,
            route: route,
            provider: provider,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            tollUSD: tollUSD,
            fuelUSD: fuelUSD,
            fuelSavingsUSD: fuelSavingsUSD,
            fuelStopName: fuelStopName,
            subtitle: kind == .fewerTolls
                ? "Standard · truck route without tolls"
                : "Premium · AI cost-benefit route",
            decisionSummary: kind == .fewerTolls
                ? "Standard plan unlocks truck-safe routes that skip tolls when possible."
                : "Premium AI balances time, tolls, diesel price, and suggested fuel stops.",
            estimatedSavingsUSD: estimatedSavingsUSD,
            recommendedStopsCount: recommendedStopsCount,
            matchesFastest: kind != .fastest   // clone da Free → esconde números repetidos no card
        )
    }
}
