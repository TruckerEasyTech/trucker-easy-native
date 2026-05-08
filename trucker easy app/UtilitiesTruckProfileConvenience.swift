//
//  TruckProfile+Convenience.swift
//  trucker easy app
//
//  Created by AI Assistant on 3/31/26.
//
//  Convenience extensions for TruckProfile to simplify routing and warning integration

import Foundation
import CoreLocation

// MARK: - TruckProfile + Routing Convenience

extension TruckProfile {
    
    /// Calculate a truck route from current location to destination
    /// - Parameters:
    ///   - origin: Starting location
    ///   - destination: Destination coordinate
    ///   - destinationName: Human-readable destination name
    ///   - avoidTolls: Whether to avoid toll roads
    /// - Returns: TruckRoute with truck-specific routing
    func calculateRoute(
        from origin: CLLocation,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        avoidTolls: Bool = false
    ) async throws -> TruckRoute {
        return try await RoutingService.shared.calculateTruckRoute(
            from: origin,
            to: destination,
            destinationName: destinationName,
            profile: self,
            avoidTolls: avoidTolls
        )
    }
    
    /// Calculate route with automatic warning generation
    /// - Parameters:
    ///   - origin: Starting location
    ///   - destination: Destination coordinate
    ///   - destinationName: Human-readable destination name
    ///   - avoidTolls: Whether to avoid toll roads
    ///   - regulations: Optional regulation profile (auto-detects if nil)
    /// - Returns: Tuple of (route, warnings)
    func calculateRouteWithWarnings(
        from origin: CLLocation,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        avoidTolls: Bool = false,
        regulations: RegulationProfile? = nil
    ) async throws -> (route: TruckRoute, warnings: [TruckRestrictionWarning]) {
        
        // Calculate route
        let route = try await calculateRoute(
            from: origin,
            to: destination,
            destinationName: destinationName,
            avoidTolls: avoidTolls
        )
        
        // Determine regulations
        let regs: RegulationProfile
        if let provided = regulations {
            regs = provided
        } else if let startCoord = route.coordinates.first {
            regs = await RegulationProfile.profile(for: startCoord)
        } else {
            regs = .generic
        }
        
        // Generate warnings
        let specs = self.toSpecifications()
        let warnings = RouteWarningEngine.evaluate(
            route: route,
            userLocation: origin,
            specs: specs,
            regulations: regs
        )
        
        return (route, warnings)
    }
    
    /// Check if this truck profile is compliant with regulations in a given country
    /// - Parameter country: Country to check compliance against
    /// - Returns: Compliance result with any violations
    func checkCompliance(in country: RegulationProfile.Country) -> ComplianceChecker.ComplianceResult {
        let profile = RegulationProfile.profile(for: country)
        let specs = self.toSpecifications()
        return ComplianceChecker.check(specs: specs, against: profile)
    }
    
    /// Check if this truck profile is compliant at a specific location
    /// - Parameter coordinate: Location to check compliance
    /// - Returns: Compliance result with any violations
    func checkCompliance(at coordinate: CLLocationCoordinate2D) async -> ComplianceChecker.ComplianceResult {
        let profile = await RegulationProfile.profile(for: coordinate)
        let specs = self.toSpecifications()
        return ComplianceChecker.check(specs: specs, against: profile)
    }
}

// NOTE: Static convenience profiles (semiFiftyThree, semiFortyEight, etc.)
// are defined as stored static properties in ModelsTruckProfile.swift — no extension needed here.

// MARK: - Example Usage

/*
 
 // Example 1: Simple route calculation
 let route = try await TruckProfile.semiFiftyThree.calculateRoute(
     from: currentLocation,
     to: destination,
     destinationName: "Los Angeles"
 )
 
 
 // Example 2: Route with automatic warnings
 let (route, warnings) = try await TruckProfile.semiFiftyThree.calculateRouteWithWarnings(
     from: currentLocation,
     to: destination,
     destinationName: "San Francisco",
     avoidTolls: true
 )
 
 print("Route: \(route.distanceMiles) miles")
 print("Warnings: \(warnings.count)")
 
 
 // Example 3: Check compliance
 let compliance = TruckProfile.oversized.checkCompliance(in: .usa)
 if compliance.hasHardViolations {
     print("⛔️ Cannot route: \(compliance.violations)")
 }
 
 
 // Example 4: Check compliance at location
 let compliance = await truckProfile.checkCompliance(at: coordinate)
 print("Compliant: \(compliance.isCompliant)")
 
 
 // Example 5: Use predefined profiles
 let standardTruck = TruckProfile.semiFiftyThree
 let boxTruck = TruckProfile.straightTruck
 let tanker = TruckProfile.tanker
 
 */
