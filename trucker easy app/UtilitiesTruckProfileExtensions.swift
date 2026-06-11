//
//  TruckProfileExtensions.swift
//  trucker easy app
//
//  Created by AI Assistant on 3/30/26.
//
//  Extensions to bridge TruckProfile with TruckSpecifications
//  and other model conversions.

import Foundation
import CoreLocation

// MARK: - TruckProfile → TruckSpecifications
extension TruckProfile {
    /// Converts TruckProfile to TruckSpecifications for routing / compliance APIs
    func toSpecifications() -> TruckSpecifications {
        // Conversão de unidades:
        // heightMeters → heightCm
        // weightTonnes → weightKg
        // lengthMeters → lengthCm
        
        let heightCm = Int(heightMeters * 100)
        let weightKg = Int(weightTonnes * 1000)
        let lengthCm = Int(lengthMeters * 100)
        let widthCm = 260 // Largura padrão de caminhão: 2.6m = 8.5 pés
        
        // Estima número de eixos baseado no tipo de caminhão
        let axleCount: Int
        switch truckType {
        case .semi:
            axleCount = 5 // Tractor (2) + Trailer (3)
        case .straight:
            axleCount = 2
        case .tanker:
            axleCount = 5
        case .flatbed:
            axleCount = 5
        case .refrigerated:
            axleCount = 5
        }
        
        let trailerCount = (truckType == .semi || truckType == .tanker || truckType == .flatbed || truckType == .refrigerated) ? 1 : 0
        
        // Peso por eixo
        let weightPerAxleKg = weightKg / axleCount
        
        // Hazmat classes
        let hazmatClasses: [String] = hasHazmat ? ["general"] : []
        
        return TruckSpecifications(
            grossWeightKg: weightKg,
            weightPerAxleKg: weightPerAxleKg,
            heightCm: heightCm,
            widthCm: widthCm,
            lengthCm: lengthCm,
            axleCount: axleCount,
            trailerCount: trailerCount,
            tunnelCategory: "B", // Safe for most tunnels
            hazardousMaterials: hazmatClasses
        )
    }
}

// MARK: - TruckRoute.RouteWarning.WarningType → TruckRestrictionWarning.WarningType
// REMOVIDO: Esta conversão não é mais necessária porque TruckRestrictionWarning
// agora tem um inicializador que aceita TruckRoute.RouteWarning diretamente.
// Veja: ViewsTruckRestrictionAlertView.swift → init(from routeWarning:)

/*
extension TruckRoute.RouteWarning.WarningType {
    func toRestrictionType() -> TruckRestrictionWarning.WarningType {
        // Conversão feita internamente em TruckRestrictionWarning
    }
}
*/

// MARK: - TruckRestrictionWarning
// Definido em: ViewsTruckRestrictionAlertView.swift
// Use TruckRestrictionWarning(from: TruckRoute.RouteWarning) para conversão


