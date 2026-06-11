-- ============================================================
-- TRUCKER EASY — Complete Migration Fix
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- 
-- This script ensures ALL 11 tables exist with every column
-- the Swift app expects. Safe to re-run multiple times.
--
-- VALIDATED AGAINST: ServicesSupabaseClient.swift structs
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. device_tokens
--    Swift: DeviceTokenPayload (driver_id, apns_token, device_model, os_version)
-- ============================================================
CREATE TABLE IF NOT EXISTS device_tokens (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id     text NOT NULL,
  apns_token    text NOT NULL UNIQUE,
  device_model  text,
  os_version    text,
  updated_at    timestamptz DEFAULT now()
);
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "driver_own_token" ON device_tokens FOR ALL USING (auth.uid()::text = driver_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- 2. drivers
--    Swift: Tables.drivers (profile data)
-- ============================================================
CREATE TABLE IF NOT EXISTS drivers (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         text UNIQUE,
  full_name     text,
  cdl_number    text,
  cdl_state     text,
  truck_type    text,
  company_id    text,
  created_at    timestamptz DEFAULT now()
);
ALTER TABLE drivers ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "driver_own_profile" ON drivers FOR ALL USING (auth.uid() = id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- 3. dispatched_loads  *** FIX: "column driver_id does not exist" ***
--    Swift: DispatchedLoadRecord
--    Query: driver_id=eq.{id}&status=eq.pending, orderBy: created_at.desc
-- ============================================================
CREATE TABLE IF NOT EXISTS dispatched_loads (
  id                    text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  driver_id             text,
  load_number           text,
  origin_address        text,
  destination_address   text,
  destination_lat       double precision,
  destination_lng       double precision,
  pickup_time           timestamptz,
  delivery_time         timestamptz,
  commodity             text,
  weight_lbs            double precision,
  special_instructions  text,
  status                text NOT NULL DEFAULT 'pending',
  company_id            text,
  company_name          text,
  valor_frete           double precision,
  preco_diesel_eia      double precision,
  received_at           timestamptz,
  started_at            timestamptz,
  delivered_at          timestamptz,
  created_at            timestamptz DEFAULT now()
);

-- NOTE: If your existing table has id as uuid (not text), that's OK.
-- PostgREST returns uuid as a JSON string, so Swift's `let id: String` works with both types.
-- The CREATE TABLE above uses `text` but won't run if the table already exists with `uuid`.

-- Add columns that may be missing from an older version of the table
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS driver_id text;
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS load_number text;
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS origin_address text;
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS destination_address text;
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS destination_lat double precision;
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS destination_lng double precision;
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS pickup_time timestamptz;
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS delivery_time timestamptz;
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS commodity text;
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS weight_lbs double precision;
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS special_instructions text;
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS status text DEFAULT 'pending';
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS company_id text;
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS company_name text;
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS valor_frete double precision;
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS preco_diesel_eia double precision;
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS received_at timestamptz;
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS started_at timestamptz;
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS delivered_at timestamptz;
ALTER TABLE dispatched_loads ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

-- Enforce NOT NULL on columns the Swift app decodes as non-optional.
-- Fill any existing NULLs first so constraints don't fail on existing rows.
UPDATE dispatched_loads SET load_number          = ''        WHERE load_number          IS NULL;
UPDATE dispatched_loads SET origin_address       = ''        WHERE origin_address       IS NULL;
UPDATE dispatched_loads SET destination_address  = ''        WHERE destination_address  IS NULL;
UPDATE dispatched_loads SET destination_lat      = 0         WHERE destination_lat      IS NULL;
UPDATE dispatched_loads SET destination_lng      = 0         WHERE destination_lng      IS NULL;
UPDATE dispatched_loads SET status               = 'pending' WHERE status               IS NULL;
UPDATE dispatched_loads SET created_at           = now()     WHERE created_at           IS NULL;

ALTER TABLE dispatched_loads ALTER COLUMN load_number         SET NOT NULL;
ALTER TABLE dispatched_loads ALTER COLUMN origin_address      SET NOT NULL;
ALTER TABLE dispatched_loads ALTER COLUMN destination_address SET NOT NULL;
ALTER TABLE dispatched_loads ALTER COLUMN destination_lat     SET NOT NULL;
ALTER TABLE dispatched_loads ALTER COLUMN destination_lng     SET NOT NULL;
ALTER TABLE dispatched_loads ALTER COLUMN status              SET NOT NULL;
ALTER TABLE dispatched_loads ALTER COLUMN created_at          SET NOT NULL;

ALTER TABLE dispatched_loads ALTER COLUMN status    SET DEFAULT 'pending';
ALTER TABLE dispatched_loads ALTER COLUMN created_at SET DEFAULT now();

ALTER TABLE dispatched_loads ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "driver_own_loads" ON dispatched_loads FOR ALL USING (auth.uid()::text = driver_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  CREATE POLICY "service_insert_loads" ON dispatched_loads FOR INSERT WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
CREATE INDEX IF NOT EXISTS idx_loads_driver_status ON dispatched_loads (driver_id, status);

-- ============================================================
-- 4. fuel_reports
--    Swift: FuelReportPayload
-- ============================================================
CREATE TABLE IF NOT EXISTS fuel_reports (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  load_id           text,
  driver_id         text NOT NULL,
  company_id        text,
  gallons           double precision NOT NULL,
  price_per_gallon  double precision NOT NULL,
  eia_average       double precision,
  savings_vs_eia    double precision,
  station_name      text,
  reported_at       timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE fuel_reports ADD COLUMN IF NOT EXISTS load_id text;
ALTER TABLE fuel_reports ADD COLUMN IF NOT EXISTS company_id text;
ALTER TABLE fuel_reports ADD COLUMN IF NOT EXISTS eia_average double precision;
ALTER TABLE fuel_reports ADD COLUMN IF NOT EXISTS savings_vs_eia double precision;
ALTER TABLE fuel_reports ADD COLUMN IF NOT EXISTS station_name text;

ALTER TABLE fuel_reports ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "driver_own_fuel" ON fuel_reports FOR ALL USING (auth.uid()::text = driver_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- 5. road_reports  *** FIX: "column reported_at does not exist" ***
--    Swift: RoadReportRecord + RoadReportPayload
--    Query: orderBy: reported_at.desc, limit 50
-- ============================================================
CREATE TABLE IF NOT EXISTS road_reports (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id     text,
  report_type   text NOT NULL,
  latitude      double precision NOT NULL,
  longitude     double precision NOT NULL,
  location_name text,
  confirmations int NOT NULL DEFAULT 0,
  reported_at   timestamptz NOT NULL DEFAULT now()
);

-- Add columns that may be missing
ALTER TABLE road_reports ADD COLUMN IF NOT EXISTS driver_id text;
ALTER TABLE road_reports ADD COLUMN IF NOT EXISTS report_type text;
ALTER TABLE road_reports ADD COLUMN IF NOT EXISTS latitude double precision;
ALTER TABLE road_reports ADD COLUMN IF NOT EXISTS longitude double precision;
ALTER TABLE road_reports ADD COLUMN IF NOT EXISTS location_name text;
ALTER TABLE road_reports ADD COLUMN IF NOT EXISTS confirmations int DEFAULT 0;
ALTER TABLE road_reports ADD COLUMN IF NOT EXISTS reported_at timestamptz DEFAULT now();

-- Enforce NOT NULL on columns the Swift app decodes as non-optional.
-- First, fill any existing NULLs with safe defaults so the constraint doesn't fail.
UPDATE road_reports SET report_type = 'unknown'       WHERE report_type IS NULL;
UPDATE road_reports SET latitude    = 0               WHERE latitude    IS NULL;
UPDATE road_reports SET longitude   = 0               WHERE longitude   IS NULL;
UPDATE road_reports SET reported_at = now()            WHERE reported_at IS NULL;

ALTER TABLE road_reports ALTER COLUMN report_type SET NOT NULL;
ALTER TABLE road_reports ALTER COLUMN latitude    SET NOT NULL;
ALTER TABLE road_reports ALTER COLUMN longitude   SET NOT NULL;
ALTER TABLE road_reports ALTER COLUMN reported_at SET NOT NULL;

ALTER TABLE road_reports ALTER COLUMN report_type SET DEFAULT 'unknown';
ALTER TABLE road_reports ALTER COLUMN latitude    SET DEFAULT 0;
ALTER TABLE road_reports ALTER COLUMN longitude   SET DEFAULT 0;
ALTER TABLE road_reports ALTER COLUMN reported_at SET DEFAULT now();

ALTER TABLE road_reports ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "anyone_read_reports" ON road_reports FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  CREATE POLICY "auth_insert_report" ON road_reports FOR INSERT WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- 6. weigh_station_reports
--    Swift: WeighStationReportRecord + WeighStationReportPayload
--    Query: orderBy: reported_at.desc, limit 100
-- ============================================================
CREATE TABLE IF NOT EXISTS weigh_station_reports (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  station_name  text NOT NULL,
  driver_id     text,
  status        text NOT NULL,
  outcome       text,
  latitude      double precision,
  longitude     double precision,
  confirmations int NOT NULL DEFAULT 0,
  reported_at   timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE weigh_station_reports ADD COLUMN IF NOT EXISTS station_name text;
ALTER TABLE weigh_station_reports ADD COLUMN IF NOT EXISTS outcome text;
ALTER TABLE weigh_station_reports ADD COLUMN IF NOT EXISTS latitude double precision;
ALTER TABLE weigh_station_reports ADD COLUMN IF NOT EXISTS longitude double precision;
ALTER TABLE weigh_station_reports ADD COLUMN IF NOT EXISTS confirmations int DEFAULT 0;
ALTER TABLE weigh_station_reports ADD COLUMN IF NOT EXISTS reported_at timestamptz DEFAULT now();

ALTER TABLE weigh_station_reports ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "anyone_read_scales" ON weigh_station_reports FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  CREATE POLICY "auth_insert_scale" ON weigh_station_reports FOR INSERT WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- 7. community_posts
--    Swift: CommunityPostRecord + CommunityPostPayload
-- ============================================================
CREATE TABLE IF NOT EXISTS community_posts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id     text,
  title         text NOT NULL,
  content       text NOT NULL,
  category      text,
  location      text,
  like_count    int NOT NULL DEFAULT 0,
  comment_count int NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS like_count int DEFAULT 0;
ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS comment_count int DEFAULT 0;

ALTER TABLE community_posts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "anyone_read_posts" ON community_posts FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  CREATE POLICY "auth_insert_post" ON community_posts FOR INSERT WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- 8. post_comments
--    Swift: PostCommentRecord + PostCommentPayload
-- ============================================================
CREATE TABLE IF NOT EXISTS post_comments (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id    uuid,
  author_id  text,
  content    text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE post_comments ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "anyone_read_comments" ON post_comments FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  CREATE POLICY "auth_insert_comment" ON post_comments FOR INSERT WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- 9. logistics_news
--    Swift: LogisticsNewsRecord
--    Query: country_code=eq.{code}, orderBy: published_at.desc
-- ============================================================
CREATE TABLE IF NOT EXISTS logistics_news (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  headline     text NOT NULL,
  summary      text,
  category     text,
  country_code text NOT NULL DEFAULT 'US',
  source       text,
  url          text,
  published_at timestamptz DEFAULT now()
);

ALTER TABLE logistics_news ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "anyone_read_news" ON logistics_news FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- 10. fleet_telemetry_stream
--     Swift: RealtimeTelemetryRecord
--     Query: select=*&order=reported_at.desc&limit=1
-- ============================================================
CREATE TABLE IF NOT EXISTS fleet_telemetry_stream (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id          text,
  speed_mph          double precision,
  engine_rpm         double precision,
  engine_hours       double precision,
  odometer_miles     double precision,
  fuel_level_percent double precision,
  vin                text,
  dtc_codes          text[] DEFAULT '{}',
  reported_at        timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE fleet_telemetry_stream ADD COLUMN IF NOT EXISTS engine_hours double precision;
ALTER TABLE fleet_telemetry_stream ADD COLUMN IF NOT EXISTS odometer_miles double precision;
ALTER TABLE fleet_telemetry_stream ADD COLUMN IF NOT EXISTS fuel_level_percent double precision;
ALTER TABLE fleet_telemetry_stream ADD COLUMN IF NOT EXISTS dtc_codes text[] DEFAULT '{}';

ALTER TABLE fleet_telemetry_stream ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "anyone_read_telemetry" ON fleet_telemetry_stream FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  CREATE POLICY "auth_insert_telemetry" ON fleet_telemetry_stream FOR INSERT WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- 11. jurisdiction_policies
--     Swift: ServicesJurisdictionPolicyService queries
-- ============================================================
CREATE TABLE IF NOT EXISTS jurisdiction_policies (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  country_code              text NOT NULL,
  state_or_province_code    text,
  max_truck_speed_kmh       double precision,
  max_gross_weight_kg       int,
  max_height_cm             int,
  max_length_cm             int,
  max_width_cm              int,
  legal_reference_url       text,
  updated_at                timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_jurisdiction_country_state
  ON jurisdiction_policies (country_code, state_or_province_code);

ALTER TABLE jurisdiction_policies ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "anyone_read_jurisdiction" ON jurisdiction_policies FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- VALIDATION: Show all columns for the two tables that had errors
-- ============================================================
SELECT '--- dispatched_loads columns ---' AS info;
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'dispatched_loads'
ORDER BY ordinal_position;

SELECT '--- road_reports columns ---' AS info;
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'road_reports'
ORDER BY ordinal_position;

-- ============================================================
-- DONE — 11 tables validated against Swift structs.
-- After running, the two HTTP 400 errors will disappear:
--   ✅ dispatched_loads.driver_id exists
--   ✅ road_reports.reported_at exists
-- ============================================================
