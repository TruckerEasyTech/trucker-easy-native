# Trucker Easy — Plano de refinamento GPS (time)

> Fonte: `Downloads/TruckerEasyGPS_Documentacao_Completa`  
> Objetivo: layout/UX tipo Trucker Path **dentro do app SwiftUI atual** — **sem** projeto UIKit paralelo.

---

## Regras que NÃO mudam

| Regra | Onde está hoje |
|-------|----------------|
| **Paleta Trucker Easy (matte gold + black)** | `UtilitiesAppConstants.swift` → `AppTheme.Colors` |
| **Globo 3D** (onboarding + estilo de mapa) | `WelcomeOnboardingView.swift`, `MapStyleOption.globe`, `HorizonIdleOverlays` |
| **Motor de rota** Valhalla + 3 opções | `RoutingService`, `RouteEasyEngine`, `ViewsHorizonView` |
| **Backend** Supabase / route-proxy / EC2 | já em produção — **UI não mexe** nesta fase |

**Não fazer:** criar app `TruckerEasyGPS` UIKit separado, copiar `TEColors` (#448aff azul) como paleta principal, remover globo, duplicar `HorizonView`.

---

## Mapeamento de cores (spec → Trucker Easy)

A spec usa azul/verde Trucker Path. **Traduzir sem trocar a marca:**

| Spec (TEColors) | Uso na spec | Trucker Easy (manter) |
|-----------------|-------------|------------------------|
| `#0d0d0d` bg | Fundo | `AppTheme.Colors.background` `#0f0d0b` |
| `#1e1e1e` / `#2a2a2a` card | Painéis | `backgroundCard` / `backgroundSecond` |
| `#448aff` primário | Go, Parking, Lane | **`AppTheme.Colors.accent`** (gold) — CTAs principais |
| `#00c853` rota | Linha rota, DEAL | `AppTheme.Colors.success` ou `accent` para rota ativa |
| `#ff5252` alerta | Clear Trip | `AppTheme.Colors.danger` |
| `#ffab40` atenção | Congestionamento, ETA chips | `AppTheme.Colors.warning` |
| `#64ffda` velocidade | Speed atual | `AppTheme.Colors.accentSoft` ou `info` dedicado |
| `#ffffff` / `#b0b0b0` texto | Tipografia | `textPrimary` / `textSecondary` |

Criar **`GPSLayoutMetrics`** (novo enum) com dimensões da spec (altura header 120pt, lane 32pt, etc.) — **não** hardcodar hex da spec nos views.

---

## Mapeamento spec → arquivos do repo

| Tela / componente (doc) | Referência UIKit (doc) | Implementar em (SwiftUI existente) |
|-------------------------|------------------------|-------------------------------------|
| Mapa principal | `TEMapViewController` | `ViewsHorizonView` + `HorizonIdleOverlays` |
| Marcador diesel | `TEFuelMarkerView` | `ViewsHorizonMapSurface` / annotations POI |
| Marcador parking | `TEParkingMarkerView` | `ViewsTruckStopView` + map pins |
| Navegação ativa | `TENavigationViewController` | `HorizonNavigationOverlays` |
| Seta manobra (6 tipos) | `TENavigationArrowView` | `NavigationManeuverIcon` → expandir ou `GPSManeuverArrowView` |
| Lane guidance | `TELaneGuidanceView` | Novo: `HorizonLaneGuidanceBar.swift` |
| Speed panel | `TESpeedPanelView` | Integrar em `HorizonNavigationStepBanner` |
| Detalhe POI | `TEPlaceDetailViewController` | `HorizonSheets` / `ViewsTruckStopView` |
| Toolbar 8 ícones | TEMap toolbar | `HorizonIdleOverlays` quick actions |
| Search + Go / Clear | TEMap bottom | `HorizonBottomSheet` |
| Globo / satélite | `.satelliteFlyover` | **`MapStyleOption.globe`** — manter seletor |

---

## Fases de execução (cada pessoa = 1 fase)

### Fase 0 — Design tokens (1 dia) · **Design + iOS lead**

- [ ] Adicionar `GPSLayoutMetrics` + `GPSComponentStyle` em `UtilitiesAppConstants.swift` (ou `GPSDesignSystem.swift`)
- [ ] Documentar mapa spec→AppTheme (tabela acima) no Figma/notion interno
- [ ] **Globo:** confirmar default idle = `.globe` ou `.satellite` (decisão produto — não remover opção)

**Entrega:** PR só com tokens, zero mudança visual ainda.

---

### Fase 1 — Mapa idle (Tela 1) · **iOS UI**

- [ ] Toolbar 8 ícones (Dir, Places, WS, Rest, Toll, Weather, Cam, Traffic) — specs de 30pt círculo, `#1e1e1e`
- [ ] Search bar 44pt + placeholder "Set destination for truck routes"
- [ ] Botões Clear Trip (danger) + Go (accent gold)
- [ ] Fuel markers: círculo 56pt, preço + DEAL (verde = `success`, não azul spec)
- [ ] Parking markers: círculo 40pt, "P" em `accent`
- [ ] Zoom +/- / recenter (já existem callbacks em `HorizonView` — só alinhar visual)
- [ ] **Manter** toggle Globe no `HorizonIdleOverlays`

**Arquivos:** `HorizonIdleOverlays.swift`, `HorizonBottomSheet.swift`, `ViewsHorizonMapSurface.swift`

**Teste:** MS→NJ idle, globo ligado, POIs visíveis.

---

### Fase 2 — Navegação ativa (Tela 3) · **iOS UI + Navigation**

- [ ] Header 120pt: distância 24pt bold, shield rota (gold/success), rua 10pt
- [ ] Lane guidance 32pt (novo componente)
- [ ] Painel lateral: próximas paradas + speed limit / MPH atual
- [ ] Summary bar 80pt: `14 mi | 14 mins` + ETA
- [ ] Anel pulsante posição (opcional v1 — `TEAnimations.pulse` port para SwiftUI)
- [ ] **Não quebrar** voz / `NavigationEngine` / recálculo rota

**Arquivos:** `HorizonNavigationOverlays.swift`, novo `HorizonLaneGuidanceBar.swift`

**Teste:** rota ativa com Valhalla, banner + lane + ETA legíveis à noite.

---

### Fase 3 — Detalhe truck stop (Tela 4) · **iOS UI + Supabase**

- [ ] Sheet 200pt: Add to trip / Plan new / Cancel
- [ ] Mapa satélite no topo do sheet (já parcial em `ViewsTruckStopView`)
- [ ] Parking MANY/SOME/FULL + review (já existe — só alinhar visual spec)

**Arquivos:** `HorizonSheets.swift`, `ViewsTruckStopView.swift`

**Teste:** login → parar em POI → review + parking.

---

### Fase 4 — Setas de manobra (Tela 5) · **iOS UI**

- [ ] 6 tipos: straight, turn R/L, exit, U-turn, roundabout
- [ ] Port visual de `TENavigationArrowView` → SwiftUI `Canvas` ou SF Symbols + overlay gold ring
- [ ] Usar em `HorizonNavigationStepBanner` + card "Then"

**Referência:** `Codigo_Swift_Xcode/Components/TENavigationArrowView.swift`

---

### Fase 5 — QA visual + TestFlight · **QA + produto**

Checklist por screenshot da spec:

- [ ] Tela 1: mapa + toolbar + search + bottom tabs
- [ ] Tela 2: zoom out + mais markers
- [ ] Tela 3: nav header + lanes + speed + summary
- [ ] Tela 4: place detail sheet
- [ ] Cores **gold**, não azul Trucker Path
- [ ] Globo onboarding + opção mapa Globe
- [ ] AI Smart / Valhalla / HOS bar intactos

---

## Quem NÃO mexe nesta sprint

| Área | Motivo |
|------|--------|
| EC2 / Valhalla / quantum | Já operacional |
| Supabase migrations | Fora escopo UI |
| `route-proxy` secrets | Fechado |
| StoreKit tiers | Só validar gates, não redesenhar paywall |

---

## Erros comuns a evitar

1. **Importar pasta `Codigo_Swift_Xcode` inteira** no target — é referência, não drop-in.
2. **Substituir `AppTheme` por `TEColors`** — perde identidade gold.
3. **Remover `MapStyleOption.globe`** — requisito explícito produto.
4. **Dois mapas** (MapView + HorizonView) divergirem — prioridade **Horizon** (tab principal).
5. **UIKit + SwiftUI** duplicados para mesma tela — só SwiftUI + `UIViewRepresentable` se unavoidable.

---

## Ordem de PRs (review fácil)

1. `GPSDesignSystem` tokens  
2. Idle map chrome (toolbar, search, markers)  
3. Navigation overlays + lane guidance  
4. Truck stop sheet polish  
5. Maneuver arrows  

Cada PR: screenshot antes/depois + **globo + gold** visíveis.

---

## Referência local

Copiar doc para o repo (opcional):

```bash
cp -R ~/Downloads/TruckerEasyGPS_Documentacao_Completa/docs/reference-gps-spec \
  "/Users/thaiskeller/Desktop/trucker easy app/docs/reference-gps-spec"
```

Spec principal: `especificacao_visual_gps.md`
