//
//  TruckLocationManager.swift
//  trucker easy app
//
//  Created by AI Assistant on 3/31/26.
//
//  Location manager for truck navigation with heading and speed

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
        
        print("📍 [Location] Manager initialized")
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // For background navigation, also request:
            // manager.requestAlwaysAuthorization()
            print("📍 [Location] Requesting authorization")
            
        case .restricted, .denied:
            print("⚠️ [Location] Access denied or restricted")
            
        case .authorizedWhenInUse, .authorizedAlways:
            print("✅ [Location] Already authorized")
            
        @unknown default:
            break
        }
    }
    
    // MARK: - Start/Stop Updates
    
    func startUpdating() {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
            print("✅ [Location] Started updating location and heading")
        case .notDetermined:
            requestAuthorization()
        case .restricted, .denied:
            print("⚠️ [Location] Cannot start updates: access denied or restricted")
        @unknown default:
            break
        }
    }
    
    func stopUpdating() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        print("⏸️ [Location] Stopped updating")
    }
    
    // MARK: - One-time Location
    
    func requestCurrentLocation() {
        manager.requestLocation()
        print("📍 [Location] Requesting one-time location")
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
            guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
            if #available(iOS 15.0, *), let source = location.sourceInformation, source.isSimulatedBySoftware {
                print("⚠️ [Location] Ignoring simulated location update")
                return
            }
            
            currentLocation = location
            speed = max(location.speed, 0)  // Negative values mean invalid
            updateMovingStatus()
            
            locationPublisher.send(location)
            
            print("📍 [Location] Updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            print("   Speed: \(String(format: "%.1f", speedMPH)) mph, Moving: \(isMoving)")
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            heading = newHeading
            headingPublisher.send(newHeading)
            print("🧭 [Location] Heading: \(Int(newHeading.trueHeading))°")
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("❌ [Location] Error: \(error.localizedDescription)")
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            
            switch authorizationStatus {
            case .notDetermined:
                print("📍 [Location] Authorization not determined")
            case .restricted:
                print("⚠️ [Location] Authorization restricted")
            case .denied:
                print("❌ [Location] Authorization denied")
            case .authorizedWhenInUse:
                print("✅ [Location] Authorized when in use")
                startUpdating()
            case .authorizedAlways:
                print("✅ [Location] Authorized always")
                startUpdating()
            @unknown default:
                break
            }
        }
    }
}
