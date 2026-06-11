-- ============================================================
-- TRUCKER EASY — Minimal Supabase schema (4 tables only)
-- Run in: Dashboard → SQL Editor → New query
-- ============================================================

create extension if not exists "pgcrypto";

-- 1) Dispatch
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
create policy "service_insert_loads" on dispatched_loads
  for insert with check (true);
create index if not exists idx_loads_driver_status
  on dispatched_loads (driver_id, status);

-- 2) Map alerts / community road reports
create table if not exists road_reports (
  id            uuid primary key default gen_random_uuid(),
  driver_id     text,
  report_type   text not null,
  latitude      double precision not null,
  longitude     double precision not null,
  location_name text,
  confirmations int not null default 0,
  reported_at   timestamptz not null default now()
);
alter table road_reports enable row level security;
create policy "anyone_read_reports" on road_reports for select using (true);
create policy "auth_insert_report"  on road_reports for insert with check (true);

-- 3) Fleet telemetry (optional UI / OBD path)
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

-- 4) Jurisdiction policy rows (optional; app falls back to built-in if empty)
create table if not exists jurisdiction_policies (
  id                     uuid primary key default gen_random_uuid(),
  country_code           text not null,
  state_or_province_code text,
  max_truck_speed_kmh    double precision,
  max_gross_weight_kg    int,
  max_height_cm          int,
  max_length_cm          int,
  max_width_cm           int,
  legal_reference_url    text,
  updated_at             timestamptz not null default now()
);
create index if not exists idx_jurisdiction_country_state
  on jurisdiction_policies (country_code, state_or_province_code);
alter table jurisdiction_policies enable row level security;
create policy "anyone_read_jurisdiction" on jurisdiction_policies for select using (true);

-- ops-feed Edge Function also reads weigh_station_reports — create if missing
create table if not exists weigh_station_reports (
  id            uuid primary key default gen_random_uuid(),
  station_name  text not null,
  driver_id     text,
  status        text not null,
  outcome       text,
  latitude      double precision,
  longitude     double precision,
  confirmations int not null default 0,
  reported_at   timestamptz not null default now()
);
alter table weigh_station_reports enable row level security;
create policy "anyone_read_scales" on weigh_station_reports for select using (true);
create policy "auth_insert_scale"  on weigh_station_reports for insert with check (true);
