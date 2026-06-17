-- Crowdsourcing de diesel: os reports crus (fuel_price_reports) são PRIVADOS (select_own, por
-- privacidade do motorista). O AGREGADO público — último preço por posto, recente — é exposto por
-- esta RPC SECURITY DEFINER (bypassa a RLS p/ servir só o agregado, sem expor quem reportou).
-- Assim o moat funciona: motorista A reporta, motorista B vê o preço (com a idade), nunca inventado.

create or replace function public.fuel_prices_near(
  p_lat double precision,
  p_lon double precision,
  p_radius_km double precision default 25,
  p_max_age_hours integer default 48,
  p_limit integer default 80
)
returns table (
  poi_place_id     uuid,
  station_name     text,
  network          text,
  latitude         double precision,
  longitude        double precision,
  diesel_price_usd numeric,
  reported_at      timestamptz,
  report_count     bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with recent as (
    select *
    from public.fuel_price_reports
    where reported_at >= now() - make_interval(hours => p_max_age_hours)
      and latitude is not null and longitude is not null
      and latitude  between p_lat - (p_radius_km / 111.0) and p_lat + (p_radius_km / 111.0)
      and longitude between p_lon - (p_radius_km / (111.0 * cos(radians(p_lat)))) and p_lon + (p_radius_km / (111.0 * cos(radians(p_lat))))
  ),
  ranked as (
    select r.*,
           row_number() over (partition by coalesce(r.poi_place_id::text, r.station_name) order by r.reported_at desc) as rn,
           count(*)     over (partition by coalesce(r.poi_place_id::text, r.station_name)) as cnt
    from recent r
  )
  select poi_place_id, station_name, network, latitude, longitude,
         diesel_price_usd, reported_at, cnt as report_count
  from ranked
  where rn = 1
  order by ((latitude - p_lat) * (latitude - p_lat) + (longitude - p_lon) * (longitude - p_lon)) asc
  limit p_limit;
$$;

grant execute on function public.fuel_prices_near(double precision, double precision, double precision, integer, integer) to anon, authenticated;
