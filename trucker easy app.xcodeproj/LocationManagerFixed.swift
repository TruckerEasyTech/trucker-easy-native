//
//  LocationManagerFixed.swift
//  Trucker Easy
//
//  LOCALIZAÇÃO FUNCIONANDO DE VERDADE!
//

import Foundation
import CoreLocation
import SwiftUI

@MainActor
class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isUpdatingLocation = false
    
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Atualiza a cada 10 metros
    }
    
    func requestPermission() {
        print("🗺️ Solicitando permissão de localização...")
        
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdatingLocation()
        case .denied, .restricted:
            print("⚠️ Permissão de localização negada")
        @unknown default:
            break
        }
    }
    
    func startUpdatingLocation() {
        print("📍 Iniciando atualizações de localização...")
        isUpdatingLocation = true
        locationManager.startUpdatingLocation()
    }
    
    func stopUpdatingLocation() {
        print("🛑 Parando atualizações de localização")
        isUpdatingLocation = false
        locationManager.stopUpdatingLocation()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            self.currentLocation = location.coordinate
            print("✅ Localização atualizada: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            
            print("🔐 Status de autorização mudou: \(manager.authorizationStatus.rawValue)")
            
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.startUpdatingLocation()
            case .denied, .restricted:
                print("❌ Usuário negou acesso à localização")
            case .notDetermined:
                print("⏳ Aguardando decisão do usuário")
            @unknown default:
                break
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Erro ao obter localização: \(error.localizedDescription)")
    }
}
