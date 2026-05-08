import Foundation
import CoreLocation

// MARK: - Protocol

protocol RoutingService {
    var isAvailable: Bool { get }
    func route(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        profile: TruckRoutingProfile
    ) async throws -> RouteResult
}

// MARK: - Errors

enum RoutingError: LocalizedError {
    case serviceUnavailable
    case invalidResponse
    case httpError(statusCode: Int)
    case requestFailed(Error)
    case networkError(Error)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "Routing service is not available"
        case .invalidResponse:
            return "Invalid response from routing service"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Data Models

struct RouteResult {
    let distance: Double      // in meters
    let duration: Int         // in seconds
    let polyline: [CLLocationCoordinate2D]
    let instructions: [RouteInstruction]
    let hasTolls: Bool
    let isTruckOptimized: Bool
}

struct RouteInstruction {
    let text: String
    let distance: Double      // in meters
    let duration: Int         // in seconds
    let type: String
}

// MARK: - Routing Chain with Fallback

actor RoutingChain {
    private let logger = os.Logger(subsystem: "com.driverfordriver.truckereasy", category: "routing")
    
    nonisolated let primaryRouter: RoutingService
    nonisolated let secondaryRouter: RoutingService
    nonisolated let tertiaryRouter: RoutingService?
    
    init(
        primary: RoutingService,
        secondary: RoutingService,
        tertiary: RoutingService? = nil
    ) {
        self.primaryRouter = primary
        self.secondaryRouter = secondary
        self.tertiaryRouter = tertiary
    }
    
    /// Execute route request with automatic fallback
    func route(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        profile: TruckRoutingProfile = .standard
    ) async throws -> RouteResult {
        // Try primary (Valhalla)
        if primaryRouter.isAvailable {
            do {
                let result = try await primaryRouter.route(from: from, to: to, profile: profile)
                logger.info("✅ Route via primary service (Valhalla)")
                return result
            } catch {
                logger.warning("⚠️ Primary router failed: \(error.localizedDescription), trying secondary...")
            }
        } else {
            logger.info("⚠️ Primary router unavailable, trying secondary...")
        }
        
        // Try secondary (OSRM)
        if secondaryRouter.isAvailable {
            do {
                let result = try await secondaryRouter.route(from: from, to: to, profile: profile)
                logger.info("✅ Route via secondary service (OSRM)")
                return result
            } catch {
                logger.warning("⚠️ Secondary router failed: \(error.localizedDescription)")
                if let tertiary = tertiaryRouter, tertiary.isAvailable {
                    logger.info("⚠️ Trying tertiary router...")
                } else {
                    logger.warning("🚫 No remaining routers available")
                }
            }
        }
        
        // Try tertiary (MapKit)
        if let tertiary = tertiaryRouter, tertiary.isAvailable {
            do {
                let result = try await tertiary.route(from: from, to: to, profile: profile)
                logger.info("✅ Route via tertiary service (MapKit)")
                return result
            } catch {
                logger.error("❌ Tertiary router failed: \(error.localizedDescription)")
                throw RoutingError.serviceUnavailable
            }
        }
        
        throw RoutingError.serviceUnavailable
    }
}

// MARK: - Stub Implementations for OSRM & MapKit

class OSRMRoutingService: RoutingService {
    static let shared = OSRMRoutingService()
    
    var isAvailable: Bool {
        // TODO: Check if OSRM server is configured
        return false
    }
    
    func route(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        profile: TruckRoutingProfile
    ) async throws -> RouteResult {
        // TODO: Implement OSRM routing
        throw RoutingError.serviceUnavailable
    }
}

class MapKitRoutingService: RoutingService {
    static let shared = MapKitRoutingService()
    
    var isAvailable: Bool {
        // MapKit is always available on iOS
        return true
    }
    
    func route(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        profile: TruckRoutingProfile
    ) async throws -> RouteResult {
        // TODO: Implement MapKit routing as fallback
        throw RoutingError.serviceUnavailable
    }
}
