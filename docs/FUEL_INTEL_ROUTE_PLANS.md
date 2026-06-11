# Fuel Intel + Route Plans

## Product Tiers

| Plan | Routing | Fuel intelligence | Driver support |
| --- | --- | --- | --- |
| Free | Conventional car route via MapKit | Regional diesel average only | Basic map |
| Standard | Valhalla truck route + avoid tolls | Station prices shown when already verified | DOT/HOS bar, truck-safe navigation |
| Premium | Route Easy / Fuel Smart route options | AI stop recommendation, savings estimate, receipt/photo reports | Food suggestions, medication timing, scale monitoring, logbook-aware guidance |

## GasBuddy Position

Do not scrape GasBuddy. Their public terms restrict automated collection. Use it only through an official partnership/API. Trucker Easy should build its own diesel network from:

- driver receipt uploads,
- price sign photos,
- manual driver reports,
- official/partner feeds where allowed,
- EIA/NRCan regional averages as fallback.

## Fuel Smart Decision

The Premium route engine should recommend a fuel stop only when savings are real:

```
savings = (route_avg_diesel - station_diesel) * gallons_needed
net_savings = savings - extra_miles_cost - extra_toll_cost
```

Recommend a stop when `net_savings > 0`, the detour is reasonable, and the stop is reachable under HOS/logbook rules.

## Data Tables

- `poi_places`: OSM/Overpass truck stops, fuel, showers, scales.
- `fuel_prices`: latest validated price per POI.
- `fuel_price_reports`: raw driver reports from manual/photo/receipt.
- `fuel_receipts`: private OCR/extraction records for receipts.

## UI Rules

- Remove raw latitude/longitude display from driver-facing map bars.
- Keep DOT/HOS bar visible; it is a core differentiator.
- Show `Fuel Smart` only on Premium.
- Show truck-aware `avoid tolls` route on Standard and Premium.
