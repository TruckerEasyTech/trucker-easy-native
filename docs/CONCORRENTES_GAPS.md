# Concorrentes — o que têm, o que o Trucker Easy já tem, e o que falta integrar

> Análise (16/06/2026) das funções que motoristas citam nos concorrentes vs o estado do app.
> Foco: integração REAL e funcional, priorizada. Sem teoria — cada gap com como integrar.

## Categorias dos concorrentes citados
- **Rastreadores hardware** (Monimoto, TKStar TK905, SpaceHawk, Teltonika, BikeTrac): anti-furto,
  localização em tempo real, alerta de movimento, bateria longa, geofencing.
- **GPS dedicados** (Garmin Dezl, Rand McNally TND): rota truck-aware, **updates de mapa vitalícios**,
  ajuste automático de fuso, limite de velocidade preciso.
- **Apps** (Trucker Path, SmartTruckRoute 2, CoPilot): **tráfego em tempo real**, **fechamentos de
  estrada diários**, achar a entrada de caminhão em embarcadores, status de balança/parada.

## ✅ O que o Trucker Easy JÁ tem (paridade/vantagem)
| Função | Status |
|---|---|
| Rota truck-aware (altura/peso/eixo/hazmat) | ✅ Valhalla truck costing |
| **Updates de mapa "vitalícios"** | ✅ **vantagem** — OSM/Valhalla é grátis e sempre atualizável (Garmin/RandMcNally cobram) |
| Restrições reais na rota (ponte/túnel/hazmat) | ✅ notices do Valhalla |
| Truck stops / balanças / status | ✅ places_near (22k POIs) + crowdsourcing (estrutura) |
| Geofencing | ✅ |
| HOS (11h/14h/pausa) | ✅ DotHosContext |
| Offline (tiles z11-16) | ✅ |
| Velocidade média/limite real | ✅ telemetria + Valhalla speed_limit |
| **Rádio (Copa/notícias) + comunidade** | ✅ **diferencial — concorrentes não têm** |

## ⚠️ Gaps a integrar (priorizados, com COMO)
1. **Tráfego em tempo real** (Trucker Path/Google/Garmin) — o maior gap.
   *Como:* Mapbox Traffic (o app já usa Mapbox; ativar a fonte de tráfego no estilo + reroute por congestionamento). Médio.
2. **Fechamentos de estrada / obras diárias** (SmartTruckRoute).
   *Como:* feeds 511 estaduais (o app já tem `backend/government-poi-ingest` p/ Caltrans/ON511/OHGO/TPIMS — estender pra closures). Backend.
3. **Fuso + ruleset HOS automático por estado** (Rand McNally).
   *Como:* detectar estado por GPS e trocar o ruleset/fuso do HOS. Já mapeado no estudo de GPS pro.
4. **"Achar meu caminhão" / localização de ativo** (equivalente software dos rastreadores).
   *Como:* salvar a última posição ao estacionar (HOS já detecta parado) + rota de volta. Leve.
5. **Entrada de caminhão em embarcador/receptor** (Trucker Path).
   *Como:* tag de "truck entrance" no crowdsourcing + exibir no POI. Depois do volume de reports.

## Princípio (o que separa o Trucker Easy do resto)
Dado REAL ou "desconhecido" — **nunca chute/simulação** (auditoria já eliminou os falsos-positivos).
Os concorrentes às vezes mostram dado velho como atual; o Trucker Easy é honesto por design.

## Recomendação de ordem
**1) Tráfego em tempo real** (maior impacto percebido) → **2) fechamentos via 511** → **3) crowdsourcing ativo**
(o moat do Trucker Path) → 4) fuso/ruleset → 5) achar-meu-caminhão. Rádio+Copa já entregue como diferencial.
