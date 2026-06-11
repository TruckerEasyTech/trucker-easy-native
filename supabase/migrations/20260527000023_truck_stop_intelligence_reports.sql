-- Trucker Easy Smart Routing support:
-- parking availability, post-stop reviews, and food metadata reported by drivers.

create extension if not exists "pgcrypto";

create table if not exists public.truck_stop_parking_reports (
  id              uuid primary key default gen_random_uuid(),
  poi_place_id    uuid references public.poi_places(id) on delete set null,
  driver_id       uuid,
  location_name   text not null,
  latitude        double precision not null check (latitude between -90 and 90),
  longitude       double precision not null check (longitude between -180 and 180),
  status          text not null check (status in ('many', 'some', 'full')),
  available_slots integer check (available_slots is null or available_slots >= 0),
  total_slots     integer check (total_slots is null or total_slots >= 0),
  source          text not null default 'driver_report'
    check (source in ('driver_report', 'partner_feed', 'prediction')),
  confidence_score numeric(4, 3) not null default 0.750
    check (confidence_score >= 0 and confidence_score <= 1),
  reported_at     timestamptz not null default now(),
  created_at      timestamptz not null default now()
);

create index if not exists idx_truck_stop_parking_reports_place_time
  on public.truck_stop_parking_reports (poi_place_id, reported_at desc)
  where poi_place_id is not null;

create index if not exists idx_truck_stop_parking_reports_geo_time
  on public.truck_stop_parking_reports (reported_at desc, latitude, longitude);

create index if not exists idx_truck_stop_parking_reports_driver_time
  on public.truck_stop_parking_reports (driver_id, reported_at desc)
  where driver_id is not null;

create table if not exists public.truck_stop_reviews (
  id                       uuid primary key default gen_random_uuid(),
  poi_place_id             uuid references public.poi_places(id) on delete set null,
  driver_id                uuid,
  location_name            text not null,
  latitude                 double precision not null check (latitude between -90 and 90),
  longitude                double precision not null check (longitude between -180 and 180),
  easy_access_rating       integer check (easy_access_rating between 1 and 5),
  cleanliness_rating       integer check (cleanliness_rating between 1 and 5),
  restaurants_rating       integer check (restaurants_rating between 1 and 5),
  friendly_service_rating  integer check (friendly_service_rating between 1 and 5),
  price_rating             integer check (price_rating between 1 and 5),
  overall_rating           numeric(3, 2) not null check (overall_rating >= 1 and overall_rating <= 5),
  restaurant_names         text[] not null default '{}',
  has_healthy_options      boolean,
  comments                 text,
  reported_at              timestamptz not null default now(),
  created_at               timestamptz not null default now()
);

create index if not exists idx_truck_stop_reviews_place_time
  on public.truck_stop_reviews (poi_place_id, reported_at desc)
  where poi_place_id is not null;

create index if not exists idx_truck_stop_reviews_geo_time
  on public.truck_stop_reviews (reported_at desc, latitude, longitude);

create index if not exists idx_truck_stop_reviews_driver_time
  on public.truck_stop_reviews (driver_id, reported_at desc)
  where driver_id is not null;

create or replace view public.truck_stop_review_summaries
with (security_invoker = true)
as
with review_base as (
  select
    poi_place_id,
    count(*)::integer as review_count,
    round(avg(overall_rating)::numeric, 2) as rating,
    bool_or(coalesce(has_healthy_options, false)) as has_healthy_options,
    max(reported_at) as last_review_at
  from public.truck_stop_reviews
  where poi_place_id is not null
  group by poi_place_id
),
restaurant_base as (
  select
    r.poi_place_id,
    array_remove(array_agg(distinct restaurant_name), null) as restaurant_names
  from public.truck_stop_reviews r
  left join lateral unnest(r.restaurant_names) restaurant_name on true
  where r.poi_place_id is not null
  group by r.poi_place_id
)
select
  rb.poi_place_id,
  rb.review_count,
  rb.rating,
  coalesce(rest.restaurant_names, '{}'::text[]) as restaurant_names,
  rb.has_healthy_options,
  rb.last_review_at
from review_base rb
left join restaurant_base rest on rest.poi_place_id = rb.poi_place_id;

create or replace view public.truck_stop_parking_latest
with (security_invoker = true)
as
select distinct on (poi_place_id)
  poi_place_id,
  status,
  available_slots,
  total_slots,
  confidence_score,
  reported_at
from public.truck_stop_parking_reports
where poi_place_id is not null
order by poi_place_id, reported_at desc;

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
  has_healthy_options boolean
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
    coalesce(rs.has_healthy_options, false) as has_healthy_options
  from public.poi_places p
  cross join origin o
  left join public.fuel_prices_latest fp on fp.poi_place_id = p.id
  left join public.truck_stop_review_summaries rs on rs.poi_place_id = p.id
  left join public.truck_stop_parking_latest pl on pl.poi_place_id = p.id
  where p.geom is not null
    and extensions.st_dwithin(p.geom, o.g, greatest(p_radius_m, 100))
    and (p_poi_types is null or p.poi_type = any (p_poi_types))
  order by extensions.st_distance(p.geom, o.g)
  limit greatest(least(p_limit, 200), 1);
$$;

grant execute on function public.places_near(double precision, double precision, double precision, text[], integer)
  to anon, authenticated, service_role;

alter table public.truck_stop_parking_reports enable row level security;
alter table public.truck_stop_reviews enable row level security;

drop policy if exists truck_stop_parking_reports_insert_own on public.truck_stop_parking_reports;
create policy truck_stop_parking_reports_insert_own
  on public.truck_stop_parking_reports
  for insert
  to authenticated
  with check (driver_id = auth.uid());

drop policy if exists truck_stop_parking_reports_select_public on public.truck_stop_parking_reports;
create policy truck_stop_parking_reports_select_public
  on public.truck_stop_parking_reports
  for select
  to anon, authenticated
  using (true);

drop policy if exists truck_stop_parking_reports_service_all on public.truck_stop_parking_reports;
create policy truck_stop_parking_reports_service_all
  on public.truck_stop_parking_reports
  for all
  to service_role
  using (true)
  with check (true);

drop policy if exists truck_stop_reviews_insert_own on public.truck_stop_reviews;
create policy truck_stop_reviews_insert_own
  on public.truck_stop_reviews
  for insert
  to authenticated
  with check (driver_id = auth.uid());

drop policy if exists truck_stop_reviews_select_public on public.truck_stop_reviews;
create policy truck_stop_reviews_select_public
  on public.truck_stop_reviews
  for select
  to anon, authenticated
  using (true);

drop policy if exists truck_stop_reviews_service_all on public.truck_stop_reviews;
create policy truck_stop_reviews_service_all
  on public.truck_stop_reviews
  for all
  to service_role
  using (true)
  with check (true);
