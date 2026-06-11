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
        cheapestFuelStop: TruckStopItem?,
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
                stop: cheapestFuelStop,
                compareTo: fastRoute
            ) {
                options.append(smart)
            } else {
                options.append(
                    makeOption(
                        kind: .fuelSmart,
                        route: noTollRoute,
                        provider: tollRoute == nil ? fastProvider : tollProvider,
                        dieselPrice: dieselPricePerGallon,
                        mpg: mpg,
                        fuelStop: cheapestFuelStop,
                        compareTo: fastRoute,
                        decisionSummary: "Premium AI balances time, tolls, diesel price, and suggested fuel stops.",
                        estimatedSavingsUSD: max(2, fastRoute.tollCostUSD * 0.15),
                        recommendedStopsCount: cheapestFuelStop == nil ? 0 : 1,
                        subtitleOverride: "Premium · AI cost-benefit route"
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
                    subtitle = "AI Smart · stop at \(stopName) saves ~$\(String(format: "%.0f", savings))"
                } else if let stopName {
                    subtitle = "AI Smart · fuel/rest option: \(stopName)"
                } else {
                    subtitle = "AI Smart · balances time, tolls, fuel and HOS"
                }
            }
        }

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
            recommendedStopsCount: recommendedStopsCount
        )
    }

    private static func aiSmartOption(
        fastRoute: TruckRoute,
        fastProvider: RoutingService.RoutingProvider,
        noTollRoute: TruckRoute,
        noTollProvider: RoutingService.RoutingProvider,
        dieselPrice: Double,
        mpg: Double,
        stop: TruckStopItem?,
        compareTo: TruckRoute
    ) -> RouteEasyOption? {
        guard stop != nil || dieselPrice > 0 else { return nil }

        let fastFuel = TripProfitability.estimateFuelCost(
            distanceMeters: fastRoute.distanceMeters,
            mpg: mpg,
            dieselPricePerGallon: dieselPrice
        )
        let noTollFuel = TripProfitability.estimateFuelCost(
            distanceMeters: noTollRoute.distanceMeters,
            mpg: mpg,
            dieselPricePerGallon: dieselPrice
        )
        let tollSavings = max(0, fastRoute.tollCostUSD - noTollRoute.tollCostUSD)
        let extraMinutes = max(0, (noTollRoute.durationSeconds - fastRoute.durationSeconds) / 60.0)
        let extraFuelCost = max(0, noTollFuel - fastFuel)
        let driverTimePenalty = extraMinutes * 0.75
        let noTollNetSavings = tollSavings - extraFuelCost - driverTimePenalty
        let shouldUseNoTollBase = noTollNetSavings > 5

        let selectedRoute = shouldUseNoTollBase ? noTollRoute : fastRoute
        let selectedProvider = shouldUseNoTollBase ? noTollProvider : fastProvider
        var savings = max(0, noTollNetSavings)
        var stopCount = 0
        var summary = shouldUseNoTollBase
            ? "Chooses the lower operating cost route after toll savings, added fuel and driver time."
            : "Chooses the fastest truck-safe base, then optimizes fuel/rest decisions along it."

        if let stop,
           let stopPrice = stop.amenities.dieselPrice,
           stopPrice < dieselPrice - 0.02 {
            let gallons = (selectedRoute.distanceMeters / 1609.34) / max(mpg, 0.1)
            let fuelSavings = (dieselPrice - stopPrice) * gallons
            savings += max(0, fuelSavings)
            stopCount = 1
            summary = "Recommends \(stop.name) because diesel is lower and the stop can support fuel/rest planning."
        }

        return makeOption(
            kind: .fuelSmart,
            route: selectedRoute,
            provider: selectedProvider,
            dieselPrice: dieselPrice,
            mpg: mpg,
            fuelStop: stop,
            compareTo: compareTo,
            decisionSummary: summary,
            estimatedSavingsUSD: savings > 1 ? savings : nil,
            recommendedStopsCount: stopCount
        )
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
            recommendedStopsCount: recommendedStopsCount
        )
    }
}
