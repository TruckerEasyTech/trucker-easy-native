# Navigation Telemetry Engine — estrutura de código

> Blueprint do "Strict Logic Engine" pedido pela Thaís. Tira a lógica de
> navegação de dentro de `ViewsHorizonView.swift` (3.4k linhas) e coloca num
> motor único, testável e leve em memória. Mapeado sobre o código que JÁ existe.
> Autor: Jarvis · 2026-06-15

## Por que isso existe (2 ganhos)
1. **Lógica única e testável** — implementa o teu `Process_Telemetry()` num lugar só.
2. **Menos RAM no app** — a `HorizonView` para de segurar estado pesado; o motor
   emite um único `NavigationState` imutável que a UI só observa.

## O contrato (o teu pseudocódigo, virado Swift)

```
Process_Telemetry(driver_data):
    1. Verify(HOS)          → se < 1h restante  → TRIGGER_ALERT(.hosCritical)
    2. Off-route?           → sim → Fetch(Valhalla) com restrições do caminhão
    3. Restrições à frente  → lookahead 3km (altura/peso/túnel/hazmat)
    4. Output               → 1 struct NavigationState (a "saída JSON")
```

## Estrutura de arquivos (novo motor + peças que já existem)

```
Utilities/
├── NavigationTelemetryEngine.swift   ← NOVO · orquestrador (@MainActor @Observable)
│       func ingest(_ tick: TelemetryTick) -> NavigationState
│
├── (existe) UtilitiesNavigationEngine.swift   → off-route, reroute, passo atual
├── (existe) UtilitiesDotHOS.swift             → DotHosContext (horas restantes)
├── (existe) EngineRouteWarningEngine.swift    → lookahead de restrições 3km
└── (existe) ServicesValhallaRoutingService.swift → rota com truck costing

Models/
├── TelemetryTick.swift     ← NOVO · entrada (1 batida de GPS)
└── NavigationState.swift   ← NOVO · saída imutável (a "saída JSON")
```

### Entrada — `TelemetryTick`
```swift
struct TelemetryTick {
    let location: CLLocation
    let speedMph: Double
    let heading: Double
    let profile: TruckProfile        // altura, peso, eixo, hazmat
    let route: TruckRoute?           // rota ativa (nil = só monitorando)
    let hos: DotHosContext           // estado de horas
}
```

### Saída — `NavigationState` (a "saída JSON")
```swift
struct NavigationState: Equatable {
    let nextManeuver: Maneuver?      // seta + texto + distância
    let etaMinutes: Int?
    let distanceRemainingMeters: Double?
    let alerts: [NavAlert]           // ordenadas por urgência
    let needsReroute: Bool
    let hosFitsETA: Bool             // pinta verde/amarelo/vermelho
}

enum NavAlert: Equatable {
    case hosCritical(minutesLeft: Int)     // PASSO 1 do contrato
    case restrictionAhead(RouteWarning)    // PASSO 3
    case offRoute
}
```

### O orquestrador — `NavigationTelemetryEngine`
```swift
@MainActor @Observable
final class NavigationTelemetryEngine {
    private(set) var state = NavigationState.idle

    func ingest(_ tick: TelemetryTick) async -> NavigationState {
        var alerts: [NavAlert] = []

        // PASSO 1 — HOS: < 1h de direção → alerta crítico
        let minsLeft = tick.hos.remainingDriveMinutes
        if minsLeft < 60 { alerts.append(.hosCritical(minutesLeft: minsLeft)) }

        // PASSO 2 — off-route → reroute com restrições do caminhão
        var needsReroute = false
        if let route = tick.route,
           NavEngine.isOffRoute(tick.location, route: route) {
            needsReroute = true
            alerts.append(.offRoute)
            // dispara reroute (debounce 30s já existe em NavigationEngine)
            Task { [weak self] in
                _ = try? await ValhallaRoutingService.shared.route(
                    from: tick.location.coordinate, to: route.destination,
                    profile: tick.profile)              // height/weight/axle/hazmat
                self?.touch()
            }
        }

        // PASSO 3 — restrições à frente (3km, filtro por direção)
        if let route = tick.route {
            let warnings = RouteWarningEngine.lookahead(
                route, from: tick.location, bearing: tick.heading, meters: 3000)
            alerts += warnings.map { .restrictionAhead($0) }
        }

        // PASSO 4 — monta a saída única
        let s = NavigationState(
            nextManeuver: tick.route.flatMap { NavEngine.maneuver(at: tick.location, on: $0) },
            etaMinutes: tick.route?.etaMinutes,
            distanceRemainingMeters: tick.route?.remaining(from: tick.location),
            alerts: alerts.sortedByUrgency(),
            needsReroute: needsReroute,
            hosFitsETA: tick.hos.fits(etaMinutes: tick.route?.etaMinutes))
        self.state = s
        return s
    }
}
```

### Como a UI usa (a `HorizonView` encolhe)
```swift
// na HorizonView, a cada update de localização:
let state = await navEngine.ingest(tick)
// a view só LÊ navEngine.state e desenha. Sem lógica, sem estado pesado.
```

## Plano de execução (cabe em < 7 dias, em fatias seguras)
- **Dia 1** — criar `TelemetryTick` + `NavigationState` + esqueleto do motor (não pluga ainda; zero risco ao build atual).
- **Dia 2** — ligar PASSO 1 (HOS) e PASSO 3 (restrições) reusando o que já existe.
- **Dia 3** — ligar PASSO 2 (off-route/reroute) e PASSO 4 (saída).
- **Dia 4** — `HorizonView` passa a LER o `state` (remove lógica duplicada → ganho de RAM).
- **Dia 5** — testes unitários do motor (entrada → saída, sem device, sem GPS simulado).
- **Folga** — buffer pra ajuste no road test real (lembrar: navegação só valida no device, não no simulador).

## Regras (do CLAUDE.md do projeto)
- SwiftUI + async/await + `@Observable`; sem Combine; sem force-unwrap.
- Não refatorar o que não foi pedido; mudanças escopadas.
- Segredos só no xcconfig.
- Validar navegação **no device** (simulador rejeita GPS simulado).
```
