//  UtilitiesCommunityTheme.swift
//  Tema da Comunidade: "Copa 2026" durante a Copa do Mundo (sediada em US/CA/MX — o mercado do app),
//  e volta SOZINHO pro tema "Logística" depois. Auto-reversão por DATA, sem update manual.
//
//  Copa do Mundo FIFA 2026: 11/06/2026 → 19/07/2026 (final). Janela aplicada abaixo.
//  Criado pelo Jarvis · 2026-06-16

import SwiftUI

enum CommunityTheme: Equatable {
    case copa
    case logistics

    /// Tema atual por DATA. Copa só na janela 11/06–19/07/2026; depois reverte automático.
    static var current: CommunityTheme {
        let cal = Calendar(identifier: .gregorian)
        guard
            let start = cal.date(from: DateComponents(year: 2026, month: 6, day: 11)),
            let endExclusive = cal.date(from: DateComponents(year: 2026, month: 7, day: 20))  // inclui o dia 19
        else { return .logistics }
        let now = Date()
        return (now >= start && now < endExclusive) ? .copa : .logistics
    }

    var isCopa: Bool { self == .copa }

    var headerTitle: String {
        switch self {
        case .copa:      return "Comunidade · Copa 2026 🏆"
        case .logistics: return "Comunidade · Logística 🚚"
        }
    }

    var accent: Color {
        switch self {
        case .copa:      return Color(hex: "#16a34a")          // verde Copa
        case .logistics: return AppTheme.Colors.accent          // ouro padrão do app
        }
    }

    var icon: String {
        switch self {
        case .copa:      return "soccerball"
        case .logistics: return "shippingbox.fill"
        }
    }

    /// Subtítulo contextual (rádio dos jogos durante a Copa; logística depois).
    var subtitle: String {
        switch self {
        case .copa:      return "Ouça os jogos no rádio e troque ideia com a estrada 🌎⚽"
        case .logistics: return "Notícias, rádio e a comunidade da estrada 🚚"
        }
    }
}
