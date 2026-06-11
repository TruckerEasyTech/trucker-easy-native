-- ============================================================
-- TRUCKER EASY — Supabase Setup SQL
-- Project (example): usowafvqawbunyhmfscx — run against your active Supabase project
-- Run this in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- Enable UUID generation
create extension if not exists "pgcrypto";

-- ============================================================
-- 1. DEVICE TOKENS (APNs push notifications for dispatch)
-- ============================================================
create table if not exists device_tokens (
  id            uuid primary key default gen_random_uuid(),
  driver_id     text not null,
  apns_token    text not null unique,
  device_model  text,
  os_version    text,
  updated_at    timestamptz default now()
);
-- RLS: drivers can only see/update their own token
alter table device_tokens enable row level security;
create policy "driver_own_token" on device_tokens
  for all using (auth.uid()::text = driver_id);

-- ============================================================
-- 2. DRIVERS (profile)
-- ============================================================
create table if not exists drivers (
  id            uuid primary key default gen_random_uuid(),
  email         text unique,
  full_name     text,
  cdl_number    text,
  cdl_state     text,
  truck_type    text,
  company_id    text,
  created_at    timestamptz default now()
);
alter table drivers enable row level security;
create policy "driver_own_profile" on drivers
  for all using (auth.uid() = id);

-- ============================================================
-- 3. DISPATCHED LOADS (core dispatch / B2B)
-- ============================================================
create table if not exists dispatched_loads (
  id                    text primary key default gen_random_uuid()::text,
  driver_id             text,
  load_number           text not null,
  origin_address        text not null,
  destination_address   text not null,
  destination_lat       double precision not null,
  destination_lng       double precision not null,
  pickup_time           timestamptz,
  delivery_time         timestamptz,
  commodity             text,
  weight_lbs            double precision,
  special_instructions  text,
  status                text not null default 'pending',
                        -- pending | received | en_route | delivered | cancelled
  company_id            text,
  company_name          text,
  valor_frete           double precision,
  preco_diesel_eia      double precision,
  received_at           timestamptz,
  started_at            timestamptz,
  delivered_at          timestamptz,
  created_at            timestamptz default now()
);
alter table dispatched_loads enable row level security;
create policy "driver_own_loads" on dispatched_loads
  for all using (auth.uid()::text = driver_id);
-- Allow service role (dispatcher / backend) to insert
create policy "service_insert_loads" on dispatched_loads
  for insert with check (true);

create index if not exists idx_loads_driver_status
  on dispatched_loads (driver_id, status);

-- ============================================================
-- 4. FUEL REPORTS (per load, feeds B2B dashboard)
-- ============================================================
create table if not exists fuel_reports (
  id                uuid primary key default gen_random_uuid(),
  load_id           text references dispatched_loads(id) on delete set null,
  driver_id         text not null,
  company_id        text,
  gallons           double precision not null,
  price_per_gallon  double precision not null,
  eia_average       double precision,
  savings_vs_eia    double precision,
  station_name      text,
  reported_at       timestamptz not null default now()
);
alter table fuel_reports enable row level security;
create policy "driver_own_fuel" on fuel_reports
  for all using (auth.uid()::text = driver_id);

-- ============================================================
-- 5. ROAD REPORTS (community hazard alerts)
-- ============================================================
create table if not exists road_reports (
  id            uuid primary key default gen_random_uuid(),
  driver_id     text,
  report_type   text not null,
                -- parkingFull | scaleOpen | scaleClosed | hazard | accident | weather
  latitude      double precision not null,
  longitude     double precision not null,
  location_name text,
  confirmations int not null default 0,
  reported_at   timestamptz not null default now()
);
alter table road_reports enable row level security;
create policy "anyone_read_reports" on road_reports for select using (true);
create policy "auth_insert_report"  on road_reports for insert with check (true);

-- ============================================================
-- 6. WEIGH STATION REPORTS
-- ============================================================
create table if not exists weigh_station_reports (
  id            uuid primary key default gen_random_uuid(),
  station_name  text not null,
  driver_id     text,
  status        text not null,   -- open | closed | monitoring
  outcome       text,            -- bypass | rollingAcross | inspection
  latitude      double precision,
  longitude     double precision,
  confirmations int not null default 0,
  reported_at   timestamptz not null default now()
);
alter table weigh_station_reports enable row level security;
create policy "anyone_read_scales" on weigh_station_reports for select using (true);
create policy "auth_insert_scale"  on weigh_station_reports for insert with check (true);

-- ============================================================
-- 7. COMMUNITY POSTS
-- ============================================================
create table if not exists community_posts (
  id            uuid primary key default gen_random_uuid(),
  author_id     text,
  title         text not null,
  content       text not null,
  category      text,   -- tips | safety | routes | general
  location      text,
  like_count    int not null default 0,
  comment_count int not null default 0,
  created_at    timestamptz not null default now()
);
alter table community_posts enable row level security;
create policy "anyone_read_posts" on community_posts for select using (true);
create policy "auth_insert_post"  on community_posts for insert with check (true);

-- ============================================================
-- 8. POST COMMENTS
-- ============================================================
create table if not exists post_comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid references community_posts(id) on delete cascade,
  author_id  text,
  content    text not null,
  created_at timestamptz not null default now()
);
alter table post_comments enable row level security;
create policy "anyone_read_comments" on post_comments for select using (true);
create policy "auth_insert_comment"  on post_comments for insert with check (true);

-- ============================================================
-- 9. LOGISTICS NEWS (admin-managed)
-- ============================================================
create table if not exists logistics_news (
  id           uuid primary key default gen_random_uuid(),
  headline     text not null,
  summary      text,
  category     text,
  country_code text not null default 'US',
  source       text,
  url          text,
  published_at timestamptz default now()
);
alter table logistics_news enable row level security;
create policy "anyone_read_news" on logistics_news for select using (true);

-- ============================================================
-- 10. FLEET TELEMETRY STREAM (optional — SupabaseRealtimeTelemetryProvider)
-- ============================================================
create table if not exists fleet_telemetry_stream (
  id                 uuid primary key default gen_random_uuid(),
  driver_id          text,
  speed_mph          double precision,
  engine_rpm         double precision,
  engine_hours       double precision,
  odometer_miles     double precision,
  fuel_level_percent double precision,
  vin                text,
  dtc_codes          text[] default '{}',
  reported_at        timestamptz not null default now()
);
alter table fleet_telemetry_stream enable row level security;
create policy "anyone_read_telemetry" on fleet_telemetry_stream for select using (true);
create policy "auth_insert_telemetry"  on fleet_telemetry_stream for insert with check (true);

-- ============================================================
-- 11. JURISDICTION POLICIES (fallback when no external policy API)
-- ============================================================
create table if not exists jurisdiction_policies (
  id                        uuid primary key default gen_random_uuid(),
  country_code              text not null,
  state_or_province_code    text,
  max_truck_speed_kmh       double precision,
  max_gross_weight_kg       int,
  max_height_cm             int,
  max_length_cm             int,
  max_width_cm              int,
  legal_reference_url       text,
  updated_at                timestamptz not null default now()
);
create index if not exists idx_jurisdiction_country_state
  on jurisdiction_policies (country_code, state_or_province_code);
alter table jurisdiction_policies enable row level security;
create policy "anyone_read_jurisdiction" on jurisdiction_policies for select using (true);

-- ============================================================
-- DONE — 11 tables. Edge Function `ops-feed` is separate (deploy via Supabase CLI if used).
-- ============================================================
