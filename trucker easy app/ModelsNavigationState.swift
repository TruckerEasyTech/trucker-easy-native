//  ModelsNavigationState.swift
//  Saída única e imutável do NavigationTelemetryEngine — a "saída JSON" do
//  Process_Telemetry. A UI (HorizonView) apenas LÊ isto e desenha; nenhuma
//  lógica de navegação fica mais na view.
//
//  Criado pelo Jarvis · 2026-06-15 · ver docs/NAVIGATION_TELEMETRY_ENGINE.md

import Foundation

/// Um alerta de navegação, já ordenável por urgência.
enum NavAlert: Equatable, Identifiable {
    /// Menos de 1h de direção DOT restante (PASSO 1 do contrato).
    case hosCritical(minutesLeft: Int)
    /// Motorista saiu da rota.
    case offRoute
    /// Restrição de caminhão à frente (altura/peso/túnel/hazmat) — PASSO 3.
    case restrictionAhead(id: String, message: String)

    var id: String {
        switch self {
        case .hosCritical:                 return "hos-critical"
        case .offRoute:                    return "off-route"
        case .restrictionAhead(let id, _): return "restriction-\(id)"
        }
    }

    /// Maior = mais urgente (vem primeiro na lista). HOS > fora-de-rota > restrição.
    var urgency: Int {
        switch self {
        case .hosCritical:    return 100
        case .offRoute:       return 80
        case .restrictionAhead: return 60
        }
    }
}

/// Estado de navegação consolidado de UMA batida de telemetria.
struct NavigationState: Equatable {
    var instruction: String?
    var etaMinutes: Int?
    var distanceRemainingMeters: Double?
    var isOffRoute: Bool
    var alerts: [NavAlert]
    /// `true` = o ETA cabe nas horas de direção restantes (pinta verde; falso = âmbar/vermelho).
    var hosFitsETA: Bool

    static let idle = NavigationState(
        instruction: nil,
        etaMinutes: nil,
        distanceRemainingMeters: nil,
        isOffRoute: false,
        alerts: [],
        hosFitsETA: true
    )
}
