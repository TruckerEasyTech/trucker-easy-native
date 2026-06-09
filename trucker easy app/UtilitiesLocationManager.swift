//
//  LocationManager.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 3/1/26.
//

import Foundation
import CoreLocation
import MapKit

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var currentLocation: CLLocation?
    var currentHeading: CLHeading?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var lastLocationError: String?
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// Best bearing available: true heading from CLHeading (more precise),
    /// falling back to GPS course when heading is unavailable.
    var bestBearing: Double {
        if let heading = currentHeading, heading.headingAccuracy >= 0 {
            return heading.trueHeading
        }
        let c = currentLocation?.course ?? -1
        if c >= 0 { return c }
        return 0
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        manager.headingFilter = 2   // Update heading when it changes ≥2 degrees (precise for truck navigation)
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        authorizationStatus = manager.authorizationStatus
    }

    /// Mission-critical battery profile switching:
    /// - Navigating: max fidelity for turn-by-turn
    /// - Idle/background ops: reduced GPS churn to save battery
    func setNavigationMode(_ isNavigating: Bool) {
        if isNavigating {
            authorizationStatus = manager.authorizationStatus
            if authorizationStatus == .authorizedWhenInUse {
                manager.requestAlwaysAuthorization()
            }
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.distanceFilter = kCLDistanceFilterNone
            manager.activityType = .automotiveNavigation
        } else {
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 15
            manager.activityType = .otherNavigation
        }
        print("[LocationManager] mode=\(isNavigating ? "nav" : "idle") accuracy=\(manager.desiredAccuracy) distanceFilter=\(manager.distanceFilter)")
    }

    func requestPermission() {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            break
        case .authorizedAlways:
            break
        case .denied, .restricted:
            lastLocationError = "Location permission denied or restricted"
            break
        @unknown default:
            break
        }
    }

    func startTracking() {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            lastLocationError = nil
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        case .notDetermined:
            requestPermission()
        case .denied, .restricted:
            lastLocationError = "Location permission denied or restricted"
            print("[LocationManager] ⚠️ \(lastLocationError ?? "Location unavailable")")
        @unknown default:
            break
        }
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }

        // In Debug/Xcode, simulated device locations are how we test GPS flows.
        // Keep rejecting simulated coordinates in release builds.
        #if !DEBUG
        if #available(iOS 15.0, *), let source = loc.sourceInformation, source.isSimulatedBySoftware {
            print("[LocationManager] ⚠️ Ignoring simulated location update")
            return
        }
        #endif

        // Accept a coarse first fix so the map can leave "GPS searching" quickly,
        // then require better accuracy for subsequent live-navigation updates.
        let maxAllowedAccuracy: CLLocationAccuracy = currentLocation == nil ? 1000 : 300
        guard loc.horizontalAccuracy <= maxAllowedAccuracy else {
            lastLocationError = "Waiting for better GPS accuracy (±\(Int(loc.horizontalAccuracy))m)"
            return
        }

        lastLocationError = nil
        currentLocation = loc
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        currentHeading = newHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let clError = error as? CLError
        // kCLErrorLocationUnknown is transient — GPS hasn't acquired yet; keep trying
        if clError?.code == .locationUnknown { return }
        // kCLErrorDenied — permission revoked at runtime; stop draining battery
        if clError?.code == .denied {
            stopTracking()
        }
        lastLocationError = error.localizedDescription
        print("[LocationManager] ❌ \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            lastLocationError = nil
            startTracking()
        case .denied, .restricted:
            lastLocationError = "Location permission denied or restricted"
            stopTracking()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func geocodeLocation(_ location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            request.getMapItems { mapItems, error in
                if let error = error {
                    print("Reverse geocoding error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                if let item = mapItems?.first,
                   let repr = item.addressRepresentations {
                    // Use MKAddressRepresentations (iOS 18+ MapKit API)
                    let city = repr.cityName ?? ""
                    let region = repr.regionName ?? ""
                    let parts = [city, region].filter { !$0.isEmpty }
                    let result = parts.joined(separator: ", ")
                    continuation.resume(returning: result.isEmpty ? nil : result)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
