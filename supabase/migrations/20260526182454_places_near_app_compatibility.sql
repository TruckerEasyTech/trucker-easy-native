-- Align the live Supabase POI schema with the iOS `PlacesNearRow` contract.
-- This keeps existing POI/fuel data and adds compatibility aliases instead of
-- replacing the older dashboard schema.

alter table public.poi_places
  add column if not exists tags jsonb not null default '{}'::jsonb,
  add column if not exists has_hgv_fuel boolean not null default false,
  add column if not exists has_weigh_station boolean not null default false,
  add column if not exists last_seen_at timestamptz not null default now();

alter table public.poi_places
  drop constraint if exists poi_places_poi_type_check;

alter table public.poi_places
  add constraint poi_places_poi_type_check
  check (poi_type in ('truck_stop', 'fuel', 'shower', 'rest_area', 'weigh_station', 'services'));

alter table public.poi_places
  drop constraint if exists poi_places_osm_type_osm_id_key;

alter table public.poi_places
  add constraint poi_places_osm_type_osm_id_poi_type_key
  unique (osm_type, osm_id, poi_type);

create or replace function public.poi_places_set_geom()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.geom := extensions.st_setsrid(extensions.st_makepoint(new.lon, new.lat), 4326)::extensions.geography;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_poi_places_set_geom on public.poi_places;
create trigger trg_poi_places_set_geom
  before insert or update of lat, lon on public.poi_places
  for each row
  execute function public.poi_places_set_geom();

update public.poi_places
set geom = extensions.st_setsrid(extensions.st_makepoint(lon, lat), 4326)::extensions.geography
where geom is null;

update public.poi_places
set has_hgv_fuel = true
where poi_type in ('fuel', 'truck_stop', 'services');

update public.poi_places
set has_weigh_station = true
where poi_type = 'weigh_station'
   or coalesce(tags->>'amenity', '') = 'weigh_station';

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'poi_places'
      and column_name = 'metadata'
  ) then
    execute $sql$
      update public.poi_places
      set tags = coalesce(nullif(tags, '{}'::jsonb), metadata, '{}'::jsonb)
      where metadata is not null
    $sql$;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'poi_places'
      and column_name = 'hgv_access'
  ) then
    execute $sql$
      update public.poi_places
      set has_hgv_fuel = true
      where coalesce(hgv_access, false) = true
    $sql$;
  end if;
end;
$$;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'fuel_prices'
      and column_name = 'price'
  ) then
    execute $sql$
      create or replace view public.fuel_prices_latest
      with (security_invoker = true)
      as
      with ranked as (
        select
          fp.id,
          fp.created_at,
          fp.updated_at,
          fp.station_id,
          fp.fuel_type,
          fp.price,
          fp.currency_code,
          fp.observed_at,
          fp.source,
          fp.metadata,
          fp.poi_place_id,
          fp.price_type,
          fp.provider,
          fp.collected_at,
          row_number() over (
            partition by coalesce(fp.poi_place_id::text, fp.station_id::text)
            order by fp.observed_at desc nulls last, fp.created_at desc nulls last
          ) as rn
        from public.fuel_prices fp
        where lower(coalesce(fp.fuel_type, '')) in ('diesel', 'diesel_b7', 'diesel_s10')
      )
      select
        id,
        created_at,
        updated_at,
        station_id,
        fuel_type,
        price,
        currency_code,
        observed_at,
        source,
        metadata,
        poi_place_id,
        price_type,
        provider,
        collected_at,
        rn,
        price as diesel_price_usd,
        observed_at as scraped_at
      from ranked
      where rn = 1
    $sql$;
  end if;
end;
$$;

drop function if exists public.places_near(double precision, double precision, integer, text[], integer);
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
  diesel_scraped_at timestamptz
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
    fp.scraped_at as diesel_scraped_at
  from public.poi_places p
  cross join origin o
  left join public.fuel_prices_latest fp on fp.poi_place_id = p.id
  where p.geom is not null
    and extensions.st_dwithin(p.geom, o.g, greatest(p_radius_m, 100))
    and (p_poi_types is null or p.poi_type = any (p_poi_types))
  order by extensions.st_distance(p.geom, o.g)
  limit greatest(least(p_limit, 200), 1);
$$;

grant execute on function public.places_near(double precision, double precision, double precision, text[], integer)
  to anon, authenticated, service_role;
