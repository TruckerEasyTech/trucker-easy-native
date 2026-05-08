//
//  TruckModels.swift
//  trucker easy app
//
//  Canonical type definitions live in their respective files:
//    TruckRoute / TruckRouteStep / TruckRouteNotice → RoutingService.swift
//    TruckProfile / TruckType                     → ModelsTruckProfile.swift
//    TruckSpecifications                          → ModelsTruckProfile.swift
//    ComplianceChecker                            → ComplianceRegulationProfile.swift
//    RegulationProfile                            → ComplianceRegulationProfile.swift
//
//  This file retains only RoutingError which is referenced across several services.

import Foundation

// MARK: - RoutingError

enum RoutingError: Error, LocalizedError {
    case engineNotInitialized
    case calculationFailed(String)
    case noRouteFound

    var errorDescription: String? {
        switch self {
        case .engineNotInitialized:
            return "Routing engine not initialized"
        case .calculationFailed(let reason):
            return "Route calculation failed: \(reason)"
        case .noRouteFound:
            return "No route found"
        }
    }
}
