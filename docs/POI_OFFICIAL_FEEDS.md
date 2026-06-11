# Fontes oficiais de POI / status operacional (Trucker Easy)

Este documento explica **de onde vêm** truck stops, showers, balanças e status open/closed — e como o app integra as mesmas classes de API que plataformas comerciais (NextBillion, HERE, agregadores 511), **sem depender de crowd de motoristas** para dados primários.

## O que NextBillion realmente é

[NextBillion.ai](https://nextbillion.ai/) é uma plataforma de **routing, navigation e Places API** — não um “Trucker Path” com motoristas reportando balança.

| API | Uso no Trucker Easy |
|-----|---------------------|
| **Browse** (`GET api.nextbillion.io/browse`) | Catálogo de POI: `truck_stop`, `fuel`, `rest_area`, `truck_parking` perto de `at=lat,lon` |
| **Search Along Route** | POI ao longo da polyline (futuro: corridor rail durante nav) |
| **Custom datasets / Multi-geocoding** | Upload de datasets próprios (ex.: NTAD enriquecido) |

NextBillion **não publica** um feed nacional único de “balança aberta/fechada”. Isso vem de **DOT estadual / 511 / NBI**, agregado por parceiros.

## Balanças: obrigação legal vs API pública

- Estações de pesagem reportam dados a **CVISN / PRISM / enforcement estadual** — sistemas para **autoridades**, não API aberta para apps de motorista.
- O que **existe publicamente** (parcial, por estado):
  - **511 / DOT** — incidentes, restrições, alguns status operacionais
  - **NBI (National Bridge Inventory)** — infraestrutura, não live open/closed
  - **USDOT NTAD** — **localização** Jason's Law parking + WIM (estático)
  - **TPIMS / OHGO** — parking dinâmico em corredores específicos

**Modelo real do mercado:** catálogo POI (HERE / OSM / NextBillion Browse) + **feeds 511/DOT agregados** (ex. Road511) + crowd como **fallback**.

## Road511 (agregador 511 / DOT / NBI)

Documentação: [road511.com/docs](https://road511.com/docs.html)

- `GET /api/v1/features?type=weigh_stations&lat=&lng=&radius_km=`
- Tipos: `weigh_stations`, `inspection_stations`, `truck_parking`, `truck_rest_areas`
- Auth: header `X-API-Key`
- Normaliza feeds estaduais onde publicados — **fonte primária de open/closed** no app quando a chave está configurada.

## Arquitetura no repo

```
Motorista (iOS)
    → ops-feed (Edge)     → Road511 + Supabase gov ops + crowd
    → trucking-poi-feed   → Road511 + NextBillion Browse → poi_places + poi_operational_status

EC2 cron
    → ingest_ntad.py           (localizações USDOT)
    → sync_operational_feeds.py (OHGO, TPIMS)
    → sync_partner_feeds.py    (Road511 + NextBillion persist)
```

### Edge Functions (Supabase secrets)

| Secret | Função |
|--------|--------|
| `ROAD511_API_KEY` | `ops-feed`, `trucking-poi-feed` |
| `NEXTBILLION_API_KEY` | `trucking-poi-feed` (Browse POI) |
| `OHGO_API_KEY` | ingest Python (parking OH) |
| `TPIMS_DYNAMIC_URLS` | ingest Python (corredor I-10 etc.) |

### Prioridade de status de balança (iOS)

1. **Road511** (511/DOT) — partner feed
2. **poi_operational_status** (gov ingest OHGO/TPIMS/Road511 persist)
3. **Crowd** (`weigh_station_reports`) — só preenche lacunas

## Configuração

1. Aplicar migration `20260527200000_government_poi_operational.sql` no Supabase.
2. Definir secrets `ROAD511_API_KEY` e `NEXTBILLION_API_KEY` no projeto Supabase.
3. Deploy das functions: `ops-feed`, `trucking-poi-feed`.
4. EC2 cron:
   ```bash
   */15 * * * * cd /path/government-poi-ingest && python3 sync_partner_feeds.py
   */10 * * * * cd /path/government-poi-ingest && python3 sync_operational_feeds.py
   0 3 * * 0 cd /path/government-poi-ingest && python3 ingest_ntad.py
   ```

## HERE (opcional)

`HERE_API_KEY` no app — Browse com categorias licenciadas (`700-7900-0131` truck parking). Complementa OSM/NTAD; não substitui 511 para balança live.

## Referências

- [NextBillion Browse API](https://docs.nextbillion.ai/places/search/search-places-api)
- [NextBillion Truck Routing](https://nextbillion.ai/solutions/truck-routing)
- [USDOT NTAD](https://data.transportation.gov/)
- [Road511 API docs](https://road511.com/docs.html)
