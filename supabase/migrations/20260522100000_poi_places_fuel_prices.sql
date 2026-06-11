-- Trucker Easy — Camada 2/3: POIs OSM (postos, chuveiros, balanças) + preços diesel
-- App consulta Supabase (places_near); ingest via script backend/osm-poi-ingest/

create extension if not exists postgis;

-- ---------------------------------------------------------------------------
-- poi_places — lista fria de POIs (Overpass / osmium → upsert semanal)
-- ---------------------------------------------------------------------------
create table if not exists public.poi_places (
  id                uuid primary key default gen_random_uuid(),
  osm_type          text not null check (osm_type in ('node', 'way', 'relation')),
  osm_id            bigint not null,
  poi_type          text not null check (poi_type in (
    'truck_stop', 'fuel', 'shower', 'rest_area', 'weigh_station', 'services'
  )),
  name              text,
  brand             text,
  operator          text,
  network           text,
  lat               double precision not null check (lat between -90 and 90),
  lon               double precision not null check (lon between -180 and 180),
  geom              geography(point, 4326),
  country_code      text check (country_code is null or country_code in ('US', 'CA')),
  tags              jsonb not null default '{}'::jsonb,
  has_shower        boolean not null default false,
  has_hgv_fuel      boolean not null default false,
  has_weigh_station boolean not null default false,
  source            text not null default 'osm',
  last_seen_at      timestamptz not null default now(),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (osm_type, osm_id, poi_type)
);

create index if not exists idx_poi_places_geom
  on public.poi_places using gist (geom);

create index if not exists idx_poi_places_poi_type
  on public.poi_places (poi_type);

create index if not exists idx_poi_places_network
  on public.poi_places (network)
  where network is not null;

create index if not exists idx_poi_places_country
  on public.poi_places (country_code);

create or replace function public.poi_places_set_geom()
returns trigger
language plpgsql
as $$
begin
  new.geom := st_setsrid(st_makepoint(new.lon, new.lat), 4326)::geography;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_poi_places_set_geom on public.poi_places;
create trigger trg_poi_places_set_geom
  before insert or update of lat, lon on public.poi_places
  for each row
  execute function public.poi_places_set_geom();

-- Backfill geom for any rows inserted without trigger (e.g. bulk SQL)
update public.poi_places
set geom = st_setsrid(st_makepoint(lon, lat), 4326)::geography
where geom is null;

-- ---------------------------------------------------------------------------
-- fuel_prices — Camada 3: preço diesel por posto (scraper diário)
-- ---------------------------------------------------------------------------
create table if not exists public.fuel_prices (
  id              uuid primary key default gen_random_uuid(),
  poi_place_id    uuid not null references public.poi_places(id) on delete cascade,
  network         text,
  diesel_price_usd numeric(8, 3) not null check (diesel_price_usd > 0),
  currency_code   text not null default 'USD',
  unit_label      text not null default 'USD/gal',
  source          text not null default 'scraper',
  scraped_at      timestamptz not null default now(),
  created_at      timestamptz not null default now()
);

create index if not exists idx_fuel_prices_poi_scraped
  on public.fuel_prices (poi_place_id, scraped_at desc);

create unique index if not exists idx_fuel_prices_one_per_day
  on public.fuel_prices (poi_place_id, ((scraped_at at time zone 'utc')::date));

-- Latest price per place (for app joins)
create or replace view public.fuel_prices_latest
with (security_invoker = true)
as
select distinct on (poi_place_id)
  id,
  poi_place_id,
  network,
  diesel_price_usd,
  currency_code,
  unit_label,
  source,
  scraped_at
from public.fuel_prices
order by poi_place_id, scraped_at desc;

-- ---------------------------------------------------------------------------
-- RPC: places_near — app busca POIs perto do motorista ou da rota
-- ---------------------------------------------------------------------------
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
  diesel_scraped_at timestamptz
)
language sql
stable
security invoker
set search_path = public
as $$
  with origin as (
    select st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography as g
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
    st_distance(p.geom, o.g) as distance_m,
    fp.diesel_price_usd,
    fp.scraped_at as diesel_scraped_at
  from public.poi_places p
  cross join origin o
  left join public.fuel_prices_latest fp on fp.poi_place_id = p.id
  where p.geom is not null
    and st_dwithin(p.geom, o.g, greatest(p_radius_m, 100))
    and (p_poi_types is null or p.poi_type = any (p_poi_types))
  order by st_distance(p.geom, o.g)
  limit greatest(least(p_limit, 200), 1);
$$;

comment on function public.places_near is
  'Returns OSM POIs within radius (meters). Default 80467 m ≈ 50 mi. Optional poi_type filter.';

grant execute on function public.places_near to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.poi_places enable row level security;
alter table public.fuel_prices enable row level security;

drop policy if exists poi_places_select_authenticated on public.poi_places;
create policy poi_places_select_authenticated
  on public.poi_places
  for select
  to authenticated, anon
  using (true);

drop policy if exists poi_places_service_all on public.poi_places;
create policy poi_places_service_all
  on public.poi_places
  for all
  to service_role
  using (true)
  with check (true);

drop policy if exists fuel_prices_select_authenticated on public.fuel_prices;
create policy fuel_prices_select_authenticated
  on public.fuel_prices
  for select
  to authenticated, anon
  using (true);

drop policy if exists fuel_prices_service_all on public.fuel_prices;
create policy fuel_prices_service_all
  on public.fuel_prices
  for all
  to service_role
  using (true)
  with check (true);
