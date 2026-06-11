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

// MARK: - Location Simulation (for testing)

extension TruckLocationManager {
    
    /// Simulate location updates along a route (for testing without GPS)
    func simulateRoute(_ route: [CLLocationCoordinate2D], speed: Double = 25.0) {
        var index = 0
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self, index < route.count else {
                timer.invalidate()
                return
            }
            
            let coord = route[index]
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            
            Task { @MainActor in
                self.currentLocation = location
                self.speed = speed
                self.updateMovingStatus()
                self.locationPublisher.send(location)
                
                #if DEBUG
                print("🎮 [Simulation] Location: \(coord.latitude), \(coord.longitude)")
                #endif
            }
            
            index += 1
        }
        
        #if DEBUG
        print("🎮 [Simulation] Started route simulation")
        #endif
    }
}

// MARK: - Example Usage

/*
 
 // Initialize
 let locationManager = TruckLocationManager()
 
 // Request authorization and start
 locationManager.startUpdating()
 
 // Get current location
 if let location = locationManager.currentLocation {
     print("Current location: \(location.coordinate)")
 }
 
 // Get speed
 print("Speed: \(locationManager.speedMPH) mph")
 
 // Check if moving
 if locationManager.isMoving {
     print("Truck is moving")
 }
 
 // Distance to destination
 let destination = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
 if let distance = locationManager.distance(to: destination) {
     print("Distance to destination: \(distance / 1609.34) miles")
 }
 
 // Bearing to destination
 if let bearing = locationManager.bearing(to: destination) {
     print("Bearing: \(Int(bearing))°")
 }
 
 // Subscribe to location updates
 locationManager.locationPublisher.sink { location in
     print("New location: \(location.coordinate)")
 }
 
 // Simulate route (for testing)
 let testRoute = [
     CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
     CLLocationCoordinate2D(latitude: 37.7849, longitude: -122.4094),
     // ... more coordinates
 ]
 locationManager.simulateRoute(testRoute, speed: 25.0)  // 25 m/s ≈ 55 mph
 
 */
