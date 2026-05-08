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
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            break
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func startTracking() {
        guard isAuthorized else {
            requestPermission()
            return
        }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Accept only accurate fixes — discard stale or low-accuracy updates
        guard let loc = locations.last, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 200 else { return }
        if #available(iOS 15.0, *), let source = loc.sourceInformation, source.isSimulatedBySoftware {
            print("[LocationManager] ⚠️ Ignoring simulated location update")
            return
        }
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
        print("[LocationManager] ❌ \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
        if isAuthorized {
            startTracking()
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
