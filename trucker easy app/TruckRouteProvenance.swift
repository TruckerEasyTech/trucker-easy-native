//
//  TruckRouteProvenance.swift
//  trucker easy app
//
//  Distinguishes **road geometry** (Valhalla / OSRM / MapKit) from **stop-order optimization**
//  returned by `POST /v1/optimize`. Quantum / hybrid solvers do not draw roads — they reorder visits;
//  the polyline is still sampled along real roads by the same geometry stack.

import Foundation

struct TruckRouteProvenance: Equatable {
    /// Engine that produced `TruckRoute.coordinates` on the map.
    var geometryProvider: RoutingService.RoutingProvider
    /// True after a successful middleware optimize call for this leg (audit IDs in `optimizeRequestId` / `solverUsed`).
    var quantumStopOrderFromAPI: Bool
    var optimizeRequestId: String?
    var solverUsed: String?

    /// HONESTO: só ganha o selo "Quantum" quem toca QPU de VERDADE — Leap Hybrid (QPU+clássico) ou
    /// Braket D-Wave (QPU). `dwave_neal_sa` (Neal = simulated annealing em CPU, apesar do nome) e
    /// `simulated_quantum_annealing` são CLÁSSICOS → NÃO podem ser anunciados como "Quantum" (era
    /// falso-positivo). Eles ainda mostram "Optimized stop order" (verdadeiro: reordenam paradas).
    var usesQuantumAccentPolyline: Bool {
        guard let s = solverUsed?.lowercased() else { return false }
        return s == "leap_hybrid_cqm" || s == "amazon_braket_dwave"
    }

    var driverBadgeTitle: String {
        if quantumStopOrderFromAPI, usesQuantumAccentPolyline { return "Quantum optimized route" }
        if quantumStopOrderFromAPI { return "Optimized stop order" }
        return "Route"
    }

    /// Short subtitle for the driver (honest about geometry vs solver).
    var driverBadgeSubtitle: String {
        let geo = geometryProvider.rawValue
        if quantumStopOrderFromAPI {
            let solver = solverUsed ?? "solver"
            if usesQuantumAccentPolyline {
                return "Stops: \(solver.replacingOccurrences(of: "_", with: " ")) · Line: \(geo)"
            }
            return "Stops: \(solver.replacingOccurrences(of: "_", with: " ")) · Line: \(geo)"
        }
        return "Line: \(geo)"
    }
}

extension TruckRoute {
    /// After `calculateTruckRoute`, attach which engine drew the polyline (preserves any prior quantum flags).
    func taggingGeometry(provider: RoutingService.RoutingProvider) -> TruckRoute {
        var r = self
        let q = r.provenance?.quantumStopOrderFromAPI ?? false
        let rid = r.provenance?.optimizeRequestId
        let sol = r.provenance?.solverUsed
        r.provenance = TruckRouteProvenance(
            geometryProvider: provider,
            quantumStopOrderFromAPI: q,
            optimizeRequestId: rid,
            solverUsed: sol
        )
        return r
    }

    /// Merge optimize middleware response into this route (geometry already computed).
    func withQuantumOptimization(from response: RouteOptimizeResponseDTO) -> TruckRoute {
        var r = self
        let geo = r.provenance?.geometryProvider ?? .unknown
        r.provenance = TruckRouteProvenance(
            geometryProvider: geo,
            quantumStopOrderFromAPI: true,
            optimizeRequestId: response.requestId,
            solverUsed: response.solverUsed
        )
        return r
    }
}
