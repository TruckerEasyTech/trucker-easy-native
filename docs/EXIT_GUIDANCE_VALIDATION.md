# Validação do Guiamento de Saída (orientação de saídas)

## Problema (road test)
As saídas apareciam **inventadas** — número de saída errado na placa "EXIT XX". Inadmissível para uso profissional/seguro.

## Causa-raiz
O app **adivinhava o número da saída por regex no TEXTO** da instrução, em vez de usar o campo
**estruturado `sign`** que o Valhalla já fornece. Regex em texto livre = fonte de invenção.

## Correção
- `ValhallaManeuver` agora decodifica `sign` (`ServicesValhallaRoutingService.swift`).
- Campos REAIS confirmados no servidor de produção: terminam em **`_elements`**
  (`exit_number_elements`, `exit_toward_elements`, `exit_branch_elements`) — **não** `exit_number`.
- Plumbado: Valhalla `sign` → `RouteStep.exitNumber/exitToward` → `DisplayRouteStep` →
  `HorizonTruckerPathNavigationChrome.exitShield/exitToward` (estruturado primeiro; regex só fallback).

## Validação (sem device — na fonte do dado e no decode)
1. **Build verde** (compila).
2. **Servidor Valhalla de produção** (`https://valhalla.truckereasy.com/route`, costing:truck) retorna:
   `"Take exit 282 on the right onto SR 194 West toward 2100 North"` com
   `exit_number_elements: [{"text":"282"}]`, `exit_toward_elements: [{"text":"2100 North"}]`.
3. **Decode em Swift (mesmas structs do app)** → `exit=282`, `toward=2100 North`. ✅

### Prova reexecutável
```
bash scripts/validate_exit_guidance.sh
```
Bate no Valhalla real + decodifica + ASSERTA `exit == 282`. Exit 0 = PASS.

## O que falta (road test — responsabilidade do motorista; nav não roda no simulador por anti-spoof)
Confirmar visualmente na estrada, rota I-15 Bluffdale→Lehi (`40.580,-111.890` → `40.415,-111.865`):
o app deve mostrar **"EXIT 282 · toward 2100 North"** batendo com a placa física.
Se divergir após este build, a causa passa a ser dado OSM do Valhalla vs placa real (tratar na fonte: tiles).
