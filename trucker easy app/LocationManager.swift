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

#if DEBUG
    /// When true (Simulator + `setDebugLocation`), Core Location updates are ignored so Valhalla/navigation can use the injected fix.
    private var debugLocationOverrideActive = false

    private var shouldIgnoreDelegateLocationsForDebugInject: Bool {
        #if targetEnvironment(simulator)
        return debugLocationOverrideActive && ProcessInfo.processInfo.environment["DISABLE_FAKE_LOCATION"] == nil
        #else
        return false
        #endif
    }
#endif

    var currentLocation: CLLocation?
    var currentHeading: CLHeading?
    /// Increments on each accepted location fix (and on heading updates so Mapbox puck bearing refreshes when stationary).
    private(set) var locationFixEpoch: UInt64 = 0
    private var lastHeadingPresentationBumpAt: Date = .distantPast
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
            // 2 m — fluid puck on highway without flooding SwiftUI (Mapbox FollowPuck interpolates between fixes).
            manager.distanceFilter = 2
            manager.activityType = .automotiveNavigation
        } else {
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 15
            manager.activityType = .otherNavigation
        }
        #if DEBUG
        print("[LocationManager] mode=\(isNavigating ? "nav" : "idle") accuracy=\(manager.desiredAccuracy) distanceFilter=\(manager.distanceFilter)")
        #endif
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
#if DEBUG
        if shouldIgnoreDelegateLocationsForDebugInject { return }
#endif
        // Accept only accurate fixes — discard stale or low-accuracy updates
        guard let loc = locations.last, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 200 else { return }
        if #available(iOS 15.0, *), let source = loc.sourceInformation, source.isSimulatedBySoftware {
            #if DEBUG
            print("[LocationManager] ⚠️ Ignoring simulated location update")
            #endif
            return
        }
        currentLocation = loc
        locationFixEpoch &+= 1
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        currentHeading = newHeading
        let now = Date()
        if now.timeIntervalSince(lastHeadingPresentationBumpAt) >= 0.22 {
            lastHeadingPresentationBumpAt = now
            locationFixEpoch &+= 1
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let clError = error as? CLError
        // kCLErrorLocationUnknown is transient — GPS hasn't acquired yet; keep trying
        if clError?.code == .locationUnknown { return }
        // kCLErrorDenied — permission revoked at runtime; stop draining battery
        if clError?.code == .denied {
            stopTracking()
        }
        #if DEBUG
        print("[LocationManager] ❌ \(error.localizedDescription)")
        #endif
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        #if DEBUG
        // Log de uma-vez (só na mudança de autorização) pra confirmar o nível no console.
        switch manager.authorizationStatus {
        case .authorizedAlways:
            print("[Location] permissão = SEMPRE ✅ — navegação em 2º plano (tela bloqueada) funciona")
        case .authorizedWhenInUse:
            print("[Location] permissão = AO USAR ⚠️ — GPS PAUSA com a tela bloqueada; escalando p/ 'Sempre'")
        case .denied, .restricted:
            print("[Location] permissão = NEGADA ❌ — sem GPS")
        case .notDetermined:
            print("[Location] permissão = ainda não decidida")
        @unknown default:
            break
        }
        #endif
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
        if isAuthorized {
            startTracking()
        }
    }

    func geocodeLocation(_ location: CLLocation) async -> String? {
        if #available(iOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
            return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                request.getMapItems { mapItems, error in
                    if let error = error {
                        #if DEBUG
                        print("Reverse geocoding error: \(error)")
                        #endif
                        continuation.resume(returning: nil)
                        return
                    }
                    if let item = mapItems?.first,
                       let repr = item.addressRepresentations {
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
        } else {
            do {
                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                guard let pm = placemarks.first else { return nil }
                let parts = [pm.locality, pm.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }
                return parts.isEmpty ? nil : parts.joined(separator: ", ")
            } catch {
                return nil
            }
        }
    }
}

#if DEBUG
extension LocationManager {
    /// Simulator: permite injetar coordenadas quando a variável de ambiente `DISABLE_FAKE_LOCATION` **não** está definida (útil porque updates “simulated by software” são ignorados no delegate).
    var useFakeLocationInSimulator: Bool {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["DISABLE_FAKE_LOCATION"] == nil
        #else
        return false
        #endif
    }

    /// Injeta um fix GPS para testes no Simulator (ex.: ponto ao longo de uma rota Valhalla). Não faz nada em device ou se `DISABLE_FAKE_LOCATION` estiver definido.
    func setDebugLocation(_ coordinate: CLLocationCoordinate2D) {
        guard useFakeLocationInSimulator else { return }
        debugLocationOverrideActive = true
        currentLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        locationFixEpoch &+= 1
        print("[LocationManager][DEBUG] setDebugLocation \(coordinate.latitude),\(coordinate.longitude)")
    }

    func clearDebugLocationOverride() {
        debugLocationOverrideActive = false
    }
}
#endif
