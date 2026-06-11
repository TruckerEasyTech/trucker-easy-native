-- Government + official operational signals for truck stops, parking, weigh stations.
-- Sources: USDOT NTAD (Jason's Law / WIM), state TPIMS/OHGO feeds (via backend sync), crowd reports.

-- Allow non-OSM POI rows (NTAD, TPIMS, HERE enrichment).
alter table public.poi_places drop constraint if exists poi_places_osm_type_check;
alter table public.poi_places
  add constraint poi_places_osm_type_check
  check (osm_type in ('node', 'way', 'relation', 'external'));

alter table public.poi_places
  add column if not exists external_source text,
  add column if not exists external_id text;

create unique index if not exists idx_poi_places_external_unique
  on public.poi_places (external_source, external_id, poi_type)
  where external_source is not null and external_id is not null;

alter table public.poi_places drop constraint if exists poi_places_external_key;
alter table public.poi_places
  add constraint poi_places_external_key
  unique (external_source, external_id, poi_type);

create index if not exists idx_poi_places_source
  on public.poi_places (source);

-- Live / semi-live status from government feeds + ingest (crowd stays in weigh_station_reports).
create table if not exists public.poi_operational_status (
  id              uuid primary key default gen_random_uuid(),
  poi_place_id    uuid not null references public.poi_places(id) on delete cascade,
  signal_type     text not null check (signal_type in ('weigh_status', 'parking_availability', 'site_open')),
  status_value    text not null,
  available_slots integer check (available_slots is null or available_slots >= 0),
  total_slots     integer check (total_slots is null or total_slots >= 0),
  source          text not null,
  source_url      text,
  confidence_score numeric(4, 3) not null default 0.850
    check (confidence_score >= 0 and confidence_score <= 1),
  observed_at     timestamptz not null default now(),
  created_at      timestamptz not null default now()
);

create index if not exists idx_poi_operational_status_place_time
  on public.poi_operational_status (poi_place_id, signal_type, observed_at desc);

create index if not exists idx_poi_operational_status_source_time
  on public.poi_operational_status (source, observed_at desc);

-- Latest official signal per POI + signal type (ingest upserts via delete+insert or append + this view).
create or replace view public.poi_operational_latest
with (security_invoker = true)
as
select distinct on (poi_place_id, signal_type)
  poi_place_id,
  signal_type,
  status_value,
  available_slots,
  total_slots,
  source,
  source_url,
  confidence_score,
  observed_at
from public.poi_operational_status
order by poi_place_id, signal_type, observed_at desc;

-- Extend places_near with government weigh/parking signals (crowd parking still from truck_stop_parking_latest).
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
as $$
  with origin as (
    select extensions.st_setsrid(extensions.st_makepoint(p_lon, p_lat), 4326)::extensions.geography as g
  )
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
    extensions.st_distance(p.geom, o.g) as distance_m,
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
    p.source as poi_source
  from public.poi_places p
  cross join origin o
  left join public.fuel_prices_latest fp on fp.poi_place_id = p.id
  left join public.truck_stop_review_summaries rs on rs.poi_place_id = p.id
  left join public.truck_stop_parking_latest pl on pl.poi_place_id = p.id
  left join public.poi_operational_latest ws
    on ws.poi_place_id = p.id and ws.signal_type = 'weigh_status'
  left join public.poi_operational_latest so
    on so.poi_place_id = p.id and so.signal_type = 'site_open'
  left join public.poi_operational_latest gp
    on gp.poi_place_id = p.id and gp.signal_type = 'parking_availability'
  where p.geom is not null
    and extensions.st_dwithin(p.geom, o.g, greatest(p_radius_m, 100))
    and (p_poi_types is null or p.poi_type = any (p_poi_types))
  order by extensions.st_distance(p.geom, o.g)
  limit greatest(least(p_limit, 200), 1);
$$;

grant execute on function public.places_near(double precision, double precision, double precision, text[], integer)
  to anon, authenticated, service_role;

alter table public.poi_operational_status enable row level security;

drop policy if exists poi_operational_status_select_public on public.poi_operational_status;
create policy poi_operational_status_select_public
  on public.poi_operational_status for select to anon, authenticated using (true);

drop policy if exists poi_operational_status_service_all on public.poi_operational_status;
create policy poi_operational_status_service_all
  on public.poi_operational_status for all to service_role using (true) with check (true);

-- Link crowd weigh reports to nearest official weigh POI when possible (within 500 m).
alter table public.weigh_station_reports
  add column if not exists poi_place_id uuid references public.poi_places(id) on delete set null;

create index if not exists idx_weigh_station_reports_poi_time
  on public.weigh_station_reports (poi_place_id, updated_at desc)
  where poi_place_id is not null;
