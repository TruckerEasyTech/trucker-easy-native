-- Câmeras de trânsito dos feeds 511 estaduais (dado público de governo, grátis). Populada pelo
-- cron sync_traffic_cameras.py. A IMAGEM é uma URL ao vivo do DOT (refresca sozinha ao abrir).
-- Idempotente (rerun-safe). Leitura pública (câmeras são públicas), escrita só service_role.

create table if not exists public.traffic_cameras (
  id          uuid primary key default gen_random_uuid(),
  source      text not null,                 -- feed/estado, ex: "511ny", "511ga"
  external_id text not null,                 -- id da câmera no feed do estado
  name        text,
  roadway     text,
  direction   text,
  latitude    double precision not null,
  longitude   double precision not null,
  image_url   text not null,                 -- URL da imagem AO VIVO (atualiza sozinha)
  video_url   text,
  disabled    boolean not null default false,
  updated_at  timestamptz not null default now(),
  unique (source, external_id)
);

create index if not exists idx_traffic_cameras_lat on public.traffic_cameras (latitude);
create index if not exists idx_traffic_cameras_lon on public.traffic_cameras (longitude);
create index if not exists idx_traffic_cameras_active on public.traffic_cameras (disabled);

alter table public.traffic_cameras enable row level security;

drop policy if exists traffic_cameras_read on public.traffic_cameras;
create policy traffic_cameras_read on public.traffic_cameras
  for select to anon, authenticated using (true);

grant select on public.traffic_cameras to anon, authenticated;

-- RPC de proximidade: câmeras dentro de um raio (km) de um ponto — o app pede só as do corredor.
create or replace function public.traffic_cameras_near(p_lat double precision, p_lon double precision, p_radius_km double precision default 25, p_limit integer default 60)
returns setof public.traffic_cameras
language sql
stable
security definer
set search_path = public
as $$
  select *
  from public.traffic_cameras
  where not disabled
    and latitude  between p_lat - (p_radius_km / 111.0) and p_lat + (p_radius_km / 111.0)
    and longitude between p_lon - (p_radius_km / (111.0 * cos(radians(p_lat)))) and p_lon + (p_radius_km / (111.0 * cos(radians(p_lat))))
  order by ((latitude - p_lat) * (latitude - p_lat) + (longitude - p_lon) * (longitude - p_lon)) asc
  limit p_limit;
$$;

grant execute on function public.traffic_cameras_near(double precision, double precision, double precision, integer) to anon, authenticated;
