//
//  MapViewModelFixed.swift
//  Trucker Easy
//
//  VIEWMODEL COM ALERTAS FUNCIONANDO
//

import Foundation
import SwiftUI
import CoreLocation
import MapKit

@MainActor
class MapViewModel: ObservableObject {
    @Published var communityAlerts: [CommunityAlert] = []
    @Published var isNavigating = false
    @Published var currentRoute: TruckRoute?
    
    init() {
        loadMockAlerts()
    }
    
    // Carregar alertas MOCK para demonstração
    func loadMockAlerts() {
        print("📍 Carregando alertas da comunidade...")
        
        communityAlerts = [
            CommunityAlert(
                id: UUID(),
                type: .weigh,
                coordinate: CLLocationCoordinate2D(latitude: 37.7849, longitude: -122.4094),
                reportedBy: "driver123",
                reportedAt: Date(),
                confirmations: 5
            ),
            CommunityAlert(
                id: UUID(),
                type: .police,
                coordinate: CLLocationCoordinate2D(latitude: 37.7649, longitude: -122.4294),
                reportedBy: "driver456",
                reportedAt: Date(),
                confirmations: 12
            ),
            CommunityAlert(
                id: UUID(),
                type: .accident,
                coordinate: CLLocationCoordinate2D(latitude: 37.7949, longitude: -122.3994),
                reportedBy: "driver789",
                reportedAt: Date(),
                confirmations: 3
            )
        ]
        
        print("✅ \(communityAlerts.count) alertas carregados")
    }
    
    func confirmAlert(_ alert: CommunityAlert) {
        print("✅ Alerta confirmado: \(alert.type.rawValue)")
        
        // Incrementar confirmações
        if let index = communityAlerts.firstIndex(where: { $0.id == alert.id }) {
            communityAlerts[index].confirmations += 1
        }
        
        // TODO: Salvar no Supabase
    }
    
    func dismissAlert(_ alert: CommunityAlert) {
        print("❌ Alerta removido: \(alert.type.rawValue)")
        
        communityAlerts.removeAll { $0.id == alert.id }
        
        // TODO: Remover do Supabase
    }
    
    func startNavigation(route: TruckRoute) {
        print("🚛 Iniciando navegação para: \(route.destinationName)")
        
        currentRoute = route
        isNavigating = true
        
        // TODO: Salvar rota no cache
    }
    
    func stopNavigation() {
        print("🛑 Parando navegação")
        
        currentRoute = nil
        isNavigating = false
    }
    
    // Adicionar novo alerta
    func addAlert(type: CommunityAlert.AlertType, at coordinate: CLLocationCoordinate2D) {
        print("➕ Adicionando alerta: \(type.rawValue)")
        
        let newAlert = CommunityAlert(
            id: UUID(),
            type: type,
            coordinate: coordinate,
            reportedBy: "current_user",
            reportedAt: Date(),
            confirmations: 1
        )
        
        communityAlerts.append(newAlert)
        
        // TODO: Salvar no Supabase
    }
}

// Extensão para CommunityAlert.AlertType com cores e ícones REAIS
extension CommunityAlert.AlertType {
    var color: Color {
        switch self {
        case .weigh: return .blue
        case .police: return .red
        case .accident: return .orange
        case .construction: return .yellow
        case .hazard: return .purple
        }
    }
    
    var icon: String {
        switch self {
        case .weigh: return "scalemass.fill"
        case .police: return "exclamationmark.shield.fill"
        case .accident: return "car.2.fill"
        case .construction: return "cone.fill"
        case .hazard: return "exclamationmark.triangle.fill"
        }
    }
}
