//  UtilitiesNavigationTelemetryEngine.swift
//  O "Strict Logic Engine" da Thaís, em Swift — versão MONTADOR (segura).
//
//  A HorizonView já dirige as peças por tick (navigationEngine.updateLocation,
//  restrictionWarningManager.updateLocation, hosContext.feedSpeed). Este motor NÃO
//  re-dirige nada (evita duplicar e quebrar o dedup/dismiss do manager): ele LÊ o
//  estado já atualizado e o consolida em UM NavigationState imutável, que a UI observa.
//
//  Process_Telemetry(assemble):
//    1. HOS      → se < 1h de direção restante → alerta crítico
//    2. Rota     → off-route (NavigationEngine já decidiu)
//    3. Restrição→ warnings já deduplicados pelo TruckRestrictionWarningManager
//    4. Saída    → 1 NavigationState (a "saída JSON")
//
//  Próximo passo (futuro, depois de provado no device): mover os drivers das
//  linhas 1699–1707 da HorizonView para dentro deste motor.
//
//  Criado pelo Jarvis · 2026-06-15 · ver docs/NAVIGATION_TELEMETRY_ENGINE.md

import Foundation
import Observation

@MainActor
@Observable
final class NavigationTelemetryEngine {

    /// Última saída consolidada. A UI lê isto e desenha — sem lógica na view.
    private(set) var state: NavigationState = .idle

    /// Limite do alerta crítico de HOS: menos de 1 hora de direção restante.
    private let hosCriticalSeconds: TimeInterval = 3600

    /// Consolida o estado de navegação a partir das peças JÁ atualizadas neste tick.
    /// Sem efeitos colaterais: só lê e monta. `warnings` vem do
    /// TruckRestrictionWarningManager (já deduplicado e filtrado por "dispensados").
    @discardableResult
    func assemble(hos: DotHosContext,
                  nav: NavigationEngine,
                  warnings: [TruckRestrictionWarning]) -> NavigationState {
        var alerts: [NavAlert] = []

        // PASSO 1 — HOS: menos de 1h de direção restante (só com o timer rodando).
        if hos.status == .driving && hos.drivingRemaining < hosCriticalSeconds {
            let minsLeft = max(0, Int(hos.drivingRemaining / 60))
            alerts.append(.hosCritical(minutesLeft: minsLeft))
        }

        // PASSO 2 — Off-route (o NavigationEngine já avaliou neste tick).
        if nav.isOffRoute {
            alerts.append(.offRoute)
        }

        // PASSO 3 — Restrições à frente (já calculadas/deduplicadas pelo manager).
        alerts.append(contentsOf: warnings.map {
            NavAlert.restrictionAhead(id: $0.id, message: $0.message)
        })

        // PASSO 4 — Monta a saída única (ordenada por urgência).
        let etaMinutes = nav.timeRemaining > 0 ? Int(nav.timeRemaining / 60) : nil
        let newState = NavigationState(
            instruction: nav.currentInstruction,
            etaMinutes: etaMinutes,
            distanceRemainingMeters: nav.distanceRemaining > 0 ? nav.distanceRemaining : nil,
            isOffRoute: nav.isOffRoute,
            alerts: alerts.sorted { $0.urgency > $1.urgency },
            hosFitsETA: hosFitsETA(hos: hos, etaSeconds: nav.timeRemaining)
        )

        #if DEBUG
        // Prova no console do device — loga só quando o estado relevante MUDA (sem spam).
        if newState.alerts != state.alerts || newState.hosFitsETA != state.hosFitsETA {
            print("[Telemetry] alerts=\(newState.alerts.count) "
                + "eta=\(newState.etaMinutes ?? -1)min "
                + "hosFits=\(newState.hosFitsETA) offRoute=\(newState.isOffRoute)")
        }
        #endif

        state = newState
        return newState
    }

    /// Reinicia para o estado ocioso (ex.: ao encerrar a navegação).
    func reset() {
        state = .idle
    }

    /// O ETA cabe nas horas de direção DOT restantes?
    private func hosFitsETA(hos: DotHosContext, etaSeconds: TimeInterval) -> Bool {
        guard etaSeconds > 0 else { return true }
        return hos.drivingRemaining >= etaSeconds
    }
}
