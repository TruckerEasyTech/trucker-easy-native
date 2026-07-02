-- Expande o CHECK de poi_type: low_bridge (ingest NBI/FHWA) + stop e rail_crossing
-- (o cliente e o ingest de sinalização JÁ usavam esses dois — a constraint antiga os
-- rejeitava silenciosamente no upsert: bug latente encontrado em 01/07/2026).
-- APLICADO EM PRODUÇÃO em 01/07/2026 via Management API; arquivo mantém o histórico.
ALTER TABLE public.poi_places DROP CONSTRAINT IF EXISTS poi_places_poi_type_check;
ALTER TABLE public.poi_places ADD CONSTRAINT poi_places_poi_type_check
  CHECK (poi_type = ANY (ARRAY[
    'truck_stop','fuel','shower','rest_area','weigh_station','services',
    'traffic_signals','stop','rail_crossing','low_bridge'
  ]));
