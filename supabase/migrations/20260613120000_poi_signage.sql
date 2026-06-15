-- Route signage (in-city, route-aware): allow OSM traffic signals + stop signs in poi_places.
--
-- The app ingests highway=traffic_signals and highway=stop nodes via the existing Overpass
-- pipeline (backend/osm-poi-ingest) and queries them through places_near(p_poi_types =>
-- '{traffic_signals,stop}'). RouteSignageService then keeps only the points that fall inside
-- the active route corridor, so the navigation map shows the signals/stops on the road ahead.
--
-- places_near() already filters by p_poi_types and uses the existing gist(geom) index, so no
-- function change is needed — only the poi_type CHECK has to accept the two new categories.

alter table public.poi_places
  drop constraint if exists poi_places_poi_type_check;

alter table public.poi_places
  add constraint poi_places_poi_type_check
  check (poi_type in (
    'truck_stop', 'fuel', 'shower', 'rest_area', 'weigh_station', 'services',
    'traffic_signals', 'stop'
  ));
