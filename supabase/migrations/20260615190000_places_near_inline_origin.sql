-- places_near: correção REAL de performance (16s -> ~ms).
--
-- Diagnóstico (medido ao vivo): o tempo cresce com o raio (8km=2s, 40km=15s) = assinatura de
-- SEQ SCAN. O índice gist(geom) existe e os tipos batem, mas a versão anterior usava um CTE
-- `origin` + `cross join` — isso fazia o planner NÃO empurrar a geografia da origem como constante
-- para a condição do índice, caindo em varredura sequencial das 22k linhas (st_distance spheroid
-- em todas). A migração de ANALYZE sozinha não bastou.
--
-- Correção: INLINE da geografia de origem direto no st_dwithin/st_distance (sem CTE/cross join).
-- Assim o planner trata a origem como constante por chamada e USA o índice gist. Mesma assinatura,
-- mesmas colunas, mesmos joins — só muda como a origem entra na query.

create index if not exists idx_poi_places_geom
  on public.poi_places using gist (geom);

drop function if exists public.places_near(double precision, double precision, double precision, text[], integer);

create or replace function public.places_near(
  p_lat double precision,
  p_lon double precision,
  p_radius_m double precision default 80467,
  p_poi_types text[] default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  osm_type text,
  osm_id bigint,
  poi_type text,
  name text,
  brand text,
  operator text,
  network text,
  lat double precision,
  lon double precision,
  country_code text,
  tags jsonb,
  has_shower boolean,
  has_hgv_fuel boolean,
  has_weigh_station boolean,
  distance_m double precision,
  diesel_price_usd numeric,
  diesel_scraped_at timestamptz,
  rating numeric,
  review_count integer,
  parking_status text,
  parking_available integer,
  parking_total integer,
  parking_reported_at timestamptz,
  restaurant_names text[],
  has_healthy_options boolean,
  gov_weigh_status text,
  gov_weigh_source text,
  gov_weigh_updated_at timestamptz,
  gov_site_open boolean,
  gov_parking_available integer,
  gov_parking_total integer,
  poi_source text
)
language sql
stable
security invoker
set search_path = public
set statement_timeout = '15s'
as $$
  with candidates as (
    select
      p.id,
      p.osm_type,
      p.osm_id,
      p.poi_type,
      p.name,
      p.brand,
      p.operator,
      p.network,
      p.lat,
      p.lon,
      p.country_code,
      p.tags,
      p.has_shower,
      p.has_hgv_fuel,
      p.has_weigh_station,
      p.source as poi_source,
      extensions.st_distance(
        p.geom,
        extensions.st_setsrid(extensions.st_makepoint(p_lon, p_lat), 4326)::extensions.geography
      ) as distance_m
    from public.poi_places p
    where p.geom is not null
      and extensions.st_dwithin(
        p.geom,
        extensions.st_setsrid(extensions.st_makepoint(p_lon, p_lat), 4326)::extensions.geography,
        greatest(p_radius_m, 100)
      )
      and (p_poi_types is null or p.poi_type = any (p_poi_types))
    order by extensions.st_distance(
      p.geom,
      extensions.st_setsrid(extensions.st_makepoint(p_lon, p_lat), 4326)::extensions.geography
    )
    limit greatest(least(p_limit, 80), 1)
  )
  select
    c.id,
    c.osm_type,
    c.osm_id,
    c.poi_type,
    c.name,
    c.brand,
    c.operator,
    c.network,
    c.lat,
    c.lon,
    c.country_code,
    c.tags,
    c.has_shower,
    c.has_hgv_fuel,
    c.has_weigh_station,
    c.distance_m,
    fp.diesel_price_usd,
    fp.scraped_at as diesel_scraped_at,
    rs.rating,
    rs.review_count,
    pl.status as parking_status,
    pl.available_slots as parking_available,
    pl.total_slots as parking_total,
    pl.reported_at as parking_reported_at,
    coalesce(rs.restaurant_names, '{}'::text[]) as restaurant_names,
    coalesce(rs.has_healthy_options, false) as has_healthy_options,
    ws.status_value as gov_weigh_status,
    ws.source as gov_weigh_source,
    ws.observed_at as gov_weigh_updated_at,
    case
      when so.status_value is null then null
      when lower(so.status_value) in ('true', 'open', '1', 'yes') then true
      when lower(so.status_value) in ('false', 'closed', '0', 'no') then false
      else null
    end as gov_site_open,
    gp.available_slots as gov_parking_available,
    gp.total_slots as gov_parking_total,
    c.poi_source
  from candidates c
  left join public.fuel_prices_latest fp on fp.poi_place_id = c.id
  left join public.truck_stop_review_summaries rs on rs.poi_place_id = c.id
  left join public.truck_stop_parking_latest pl on pl.poi_place_id = c.id
  left join public.poi_operational_latest ws
    on ws.poi_place_id = c.id and ws.signal_type = 'weigh_status'
  left join public.poi_operational_latest so
    on so.poi_place_id = c.id and so.signal_type = 'site_open'
  left join public.poi_operational_latest gp
    on gp.poi_place_id = c.id and gp.signal_type = 'parking_availability'
  order by c.distance_m;
$$;

grant execute on function public.places_near(double precision, double precision, double precision, text[], integer)
  to anon, authenticated, service_role;

analyze public.poi_places;
