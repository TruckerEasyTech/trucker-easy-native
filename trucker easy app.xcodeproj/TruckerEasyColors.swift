//
//  TruckerEasyColors.swift
//  Trucker Easy
//
//  CORES EXATAS DO LOVABLE + TRUCKER PATH
//

import SwiftUI

extension Color {
    // CORES PRINCIPAIS (do Lovable)
    static let truckerPrimary = Color(hex: "#FF6B35")      // Laranja principal
    static let truckerSecondary = Color(hex: "#004E89")    // Azul escuro
    static let truckerAccent = Color(hex: "#1A936F")       // Verde
    static let truckerDark = Color(hex: "#1E1E1E")         // Fundo escuro
    static let truckerLight = Color(hex: "#F5F5F5")        // Fundo claro
    
    // CORES DE STATUS (semáforo)
    static let statusGreen = Color(hex: "#10B981")         // Verde
    static let statusYellow = Color(hex: "#F59E0B")        // Amarelo
    static let statusRed = Color(hex: "#EF4444")           // Vermelho
    
    // CORES DE ALERTA
    static let alertPolice = Color(hex: "#DC2626")         // Vermelho polícia
    static let alertWeigh = Color(hex: "#3B82F6")          // Azul balança
    static let alertAccident = Color(hex: "#F97316")       // Laranja acidente
    static let alertConstruction = Color(hex: "#EAB308")   // Amarelo construção
    
    // HELPER para hex
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
