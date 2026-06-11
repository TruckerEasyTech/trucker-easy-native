//
//  RouteWarningEngine.swift
//  trucker easy app
//
//  Created by AI Assistant on 3/31/26.
//
//  Smart route warning engine with lookahead, bearing-aware filtering,
//  and compliance-based alert generation for truck routing.

import Foundation
import CoreLocation

// MARK: - Route Warning Engine

/// Generates intelligent truck restriction warnings based on route, location, specs, and regulations
@MainActor
struct RouteWarningEngine {
    
    // MARK: - Configuration
    
    static let lookaheadDistanceMeters: Double = 3000  // 3km warning distance
    static let bearingToleranceDegrees: Double = 45    // ±45° cone for direction filtering
    
    // MARK: - Evaluate Route
    
    /// Evaluates a truck route and generates contextual warnings
    /// - Parameters:
    ///   - route: The calculated truck route (can be TruckRoute or TruckRoute)
    ///   - userLocation: Current GPS location of the truck
    ///   - specs: Truck specifications
    ///   - regulations: Regional regulation profile
    /// - Returns: Array of TruckRestrictionWarning sorted by distance
    static func evaluate(
        route: TruckRoute,
        userLocation: CLLocation,
        specs: TruckSpecifications,
        regulations: RegulationProfile,
        language: AppLanguage
    ) -> [TruckRestrictionWarning] {
        var warnings: [TruckRestrictionWarning] = []

        // 1. Check compliance violations
        let complianceResult = ComplianceChecker.check(specs: specs, against: regulations, language: language)
        if !complianceResult.isCompliant {
            warnings.append(contentsOf: complianceWarnings(from: complianceResult, location: userLocation.coordinate))
        }
        
        // 2. Extract truck-specific notices from routing API responses
        warnings.append(contentsOf: extractNoticeWarnings(from: route, userLocation: userLocation))
        
        // 3. Filter by lookahead distance and bearing
        warnings = filterByProximityAndBearing(
            warnings: warnings,
            userLocation: userLocation,
            routeCoordinates: route.coordinates
        )
        
        // 4. Sort by distance (closest first)
        warnings.sort { w1, w2 in
            let d1 = distance(from: userLocation, to: w1) ?? .infinity
            let d2 = distance(from: userLocation, to: w2) ?? .infinity
            return d1 < d2
        }
        
        return warnings
    }
    
    // MARK: - Compliance Warnings
    
    /// Converts compliance violations into warnings
    private static func complianceWarnings(
        from result: ComplianceChecker.ComplianceResult,
        location: CLLocationCoordinate2D
    ) -> [TruckRestrictionWarning] {
        result.violations.map { violation in
            let type: TruckRestrictionWarning.WarningType
            let message: String
            
            switch violation.type {
            case .height:
                type = .heightLimit
                message = "⚠️ \(violation.message)"
            case .weight:
                type = .weightLimit
                message = "⚠️ \(violation.message)"
            case .length:
                type = .general
                message = "⚠️ \(violation.message)"
            case .width:
                type = .narrowRoad
                message = "⚠️ \(violation.message)"
            }
            
            return TruckRestrictionWarning(
                type: type,
                message: message,
                coordinate: location
            )
        }
    }
    
    // MARK: - Notice Warnings
    
    /// Extracts warnings from route notices (truck restrictions detected by API)
    private static func extractNoticeWarnings(
        from route: TruckRoute,
        userLocation: CLLocation
    ) -> [TruckRestrictionWarning] {
        route.truckNotices.compactMap { notice in
            guard let coordinate = notice.coordinate else { return nil }

            let type = mapNoticeCodeToWarningType(notice.code)
            let message = notice.details ?? notice.title

            return TruckRestrictionWarning(
                type: type,
                message: message,
                coordinate: coordinate
            )
        }
    }
    
    /// Maps provider notice codes to TruckRestrictionWarning types
    private static func mapNoticeCodeToWarningType(_ code: String) -> TruckRestrictionWarning.WarningType {
        let lowerCode = code.lowercased()
        
        if lowerCode.contains("height") || lowerCode.contains("bridge") || lowerCode.contains("clearance") {
            return .lowBridge
        } else if lowerCode.contains("weight") || lowerCode.contains("gross") || lowerCode.contains("axle") {
            return .weightLimit
        } else if lowerCode.contains("tunnel") {
            return .tunnel
        } else if lowerCode.contains("hazmat") || lowerCode.contains("hazardous") {
            return .hazmat
        } else if lowerCode.contains("narrow") || lowerCode.contains("width") {
            return .narrowRoad
        } else if lowerCode.contains("time") {
            return .general
        } else if lowerCode.contains("u_turn") || lowerCode.contains("uturn") {
            return .general
        } else {
            return .general
        }
    }
    
    // MARK: - Filtering
    
    /// Filters warnings by proximity (lookahead) and bearing (direction of travel)
    private static func filterByProximityAndBearing(
        warnings: [TruckRestrictionWarning],
        userLocation: CLLocation,
        routeCoordinates: [CLLocationCoordinate2D]
    ) -> [TruckRestrictionWarning] {
        
        // Calculate user's bearing from route
        guard let userBearing = calculateBearing(from: userLocation, along: routeCoordinates) else {
            // No bearing available, just filter by distance
            return warnings.filter { warning in
                guard let dist = distance(from: userLocation, to: warning) else { return false }
                return dist <= lookaheadDistanceMeters
            }
        }
        
        return warnings.filter { warning in
            guard let coord = warning.coordinate else { return false }
            
            // Distance check
            let warningLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let dist = userLocation.distance(from: warningLocation)
            guard dist <= lookaheadDistanceMeters else { return false }
            
            // Bearing check (is warning ahead of us?)
            let bearingToWarning = userLocation.coordinate.bearing(to: coord)
            let bearingDiff = abs(angleDifference(userBearing, bearingToWarning))
            
            return bearingDiff <= bearingToleranceDegrees
        }
    }
    
    // MARK: - Helper: Bearing Calculation
    
    /// Calculates user's travel bearing from their position along the route
    private static func calculateBearing(
        from userLocation: CLLocation,
        along route: [CLLocationCoordinate2D]
    ) -> Double? {
        // Find closest point on route
        guard let closestIndex = closestPointIndex(to: userLocation.coordinate, in: route),
              closestIndex < route.count - 1 else {
            return nil
        }
        
        // Bearing is from current point to next point on route
        let current = route[closestIndex]
        let next = route[closestIndex + 1]
        return current.bearing(to: next)
    }
    
    /// Finds index of closest coordinate in route to user location
    private static func closestPointIndex(
        to userCoord: CLLocationCoordinate2D,
        in route: [CLLocationCoordinate2D]
    ) -> Int? {
        guard !route.isEmpty else { return nil }
        
        var minDistance = Double.infinity
        var minIndex = 0
        
        for (index, coord) in route.enumerated() {
            let dist = userCoord.distance(to: coord)
            if dist < minDistance {
                minDistance = dist
                minIndex = index
            }
        }
        
        return minIndex
    }
    
    /// Calculate absolute difference between two angles (0-180°)
    private static func angleDifference(_ a: Double, _ b: Double) -> Double {
        var diff = abs(a - b)
        if diff > 180 {
            diff = 360 - diff
        }
        return diff
    }
    
    /// Distance from location to warning
    private static func distance(from location: CLLocation, to warning: TruckRestrictionWarning) -> Double? {
        guard let coord = warning.coordinate else { return nil }
        let warningLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return location.distance(from: warningLocation)
    }
}

// MARK: - CLLocationCoordinate2D Extensions

extension CLLocationCoordinate2D {
    /// Calculate bearing from this coordinate to another (in degrees, 0-360)
    func bearing(to destination: CLLocationCoordinate2D) -> Double {
        let lat1 = self.latitude * .pi / 180
        let lon1 = self.longitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let lon2 = destination.longitude * .pi / 180
        
        let dLon = lon2 - lon1
        
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        
        var bearing = atan2(y, x) * 180 / .pi
        bearing = (bearing + 360).truncatingRemainder(dividingBy: 360)
        
        return bearing
    }
    
    /// Calculate distance to another coordinate (in meters, Haversine formula)
    func distance(to destination: CLLocationCoordinate2D) -> Double {
        let earthRadius = 6371000.0  // meters
        
        let lat1 = self.latitude * .pi / 180
        let lon1 = self.longitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let lon2 = destination.longitude * .pi / 180
        
        let dLat = lat2 - lat1
        let dLon = lon2 - lon1
        
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        
        return earthRadius * c
    }
}
