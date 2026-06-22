//
//  ServicesTruckLocationTracking.swift
//  trucker easy app
//
//  Created by AI Assistant on 3/31/26.
//
//  Truck GPS + heading + speed for navigation surfaces (distinct from app `LocationManager` in LocationManager.swift).

import Foundation
import CoreLocation
import Combine

// MARK: - Truck Location Manager

@MainActor
@Observable
class TruckLocationManager: NSObject {
    
    // Published properties
    private(set) var currentLocation: CLLocation?
    private(set) var heading: CLHeading?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var speed: Double = 0  // meters per second
    var speedMPH: Double { speed * 2.23694 }  // Convert m/s to mph
    private(set) var isMoving: Bool = false
    
    // Location manager
    private let manager = CLLocationManager()
    
    // Settings
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBestForNavigation
    var distanceFilter: CLLocationDistance = 10  // meters
    
    // Subjects for Combine
    let locationPublisher = PassthroughSubject<CLLocation, Never>()
    let headingPublisher = PassthroughSubject<CLHeading, Never>()
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    // MARK: - Setup
    
    private func setupLocationManager() {
        manager.delegate = self
        manager.desiredAccuracy = desiredAccuracy
        manager.distanceFilter = distanceFilter
        manager.activityType = .automotiveNavigation
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        
        authorizationStatus = manager.authorizationStatus
        
        #if DEBUG
        print("📍 [Location] Manager initialized")
        #endif
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // For background navigation, also request:
            // manager.requestAlwaysAuthorization()
            #if DEBUG
            print("📍 [Location] Requesting authorization")
            #endif
            
        case .restricted, .denied:
            #if DEBUG
            print("⚠️ [Location] Access denied or restricted")
            #endif
            
        case .authorizedWhenInUse, .authorizedAlways:
            #if DEBUG
            print("✅ [Location] Already authorized")
            #endif
            
        @unknown default:
            break
        }
    }
    
    // MARK: - Start/Stop Updates
    
    func startUpdating() {
        requestAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        #if DEBUG
        print("✅ [Location] Started updating location and heading")
        #endif
    }
    
    func stopUpdating() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        #if DEBUG
        print("⏸️ [Location] Stopped updating")
        #endif
    }
    
    // MARK: - One-time Location
    
    func requestCurrentLocation() {
        manager.requestLocation()
        #if DEBUG
        print("📍 [Location] Requesting one-time location")
        #endif
    }
    
    // MARK: - Helpers
    
    /// Distance to coordinate in meters
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard let location = currentLocation else { return nil }
        let destination = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location.distance(from: destination)
    }
    
    /// Bearing to coordinate in degrees (0-360)
    func bearing(to coordinate: CLLocationCoordinate2D) -> Double? {
        guard let location = currentLocation else { return nil }
        return location.coordinate.bearing(to: coordinate)
    }
    
    /// Check if moving (speed > threshold)
    private func updateMovingStatus() {
        let threshold: Double = 1.0  // 1 m/s ≈ 2.2 mph
        isMoving = speed > threshold
    }
}

// MARK: - CLLocationManagerDelegate

extension TruckLocationManager: CLLocationManagerDelegate {
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            
            currentLocation = location
            speed = max(location.speed, 0)  // Negative values mean invalid
            updateMovingStatus()
            
            locationPublisher.send(location)
            
            #if DEBUG
            print("📍 [Location] Updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            #endif
            #if DEBUG
            print("   Speed: \(String(format: "%.1f", speedMPH)) mph, Moving: \(isMoving)")
            #endif
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            heading = newHeading
            headingPublisher.send(newHeading)
            #if DEBUG
            print("🧭 [Location] Heading: \(Int(newHeading.trueHeading))°")
            #endif
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            #if DEBUG
            print("❌ [Location] Error: \(error.localizedDescription)")
            #endif
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            
            switch authorizationStatus {
            case .notDetermined:
                #if DEBUG
                print("📍 [Location] Authorization not determined")
                #endif
            case .restricted:
                #if DEBUG
                print("⚠️ [Location] Authorization restricted")
                #endif
            case .denied:
                #if DEBUG
                print("❌ [Location] Authorization denied")
                #endif
            case .authorizedWhenInUse:
                #if DEBUG
                print("✅ [Location] Authorized when in use")
                #endif
                startUpdating()
            case .authorizedAlways:
                #if DEBUG
                print("✅ [Location] Authorized always")
                #endif
                startUpdating()
            @unknown default:
                break
            }
        }
    }
}

// Simulador de GPS REMOVIDO (19/06): `simulateRoute` injetava localização falsa ("🎮 [Simulation]")
// e o exemplo de uso tinha coords de teste hardcoded. Era código MORTO (TruckLocationManager só era
// usado na nav LEGADA, fora das tabs reais — a nav real é HorizonView). App de estrada real não
// carrega injetor de GPS fake nem como mina inativa.
