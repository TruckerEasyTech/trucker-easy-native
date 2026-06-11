-- Trucker Easy Fuel Intel — driver price reports + receipt evidence
-- Builds our own diesel-price network instead of scraping restricted sources.

create extension if not exists "pgcrypto";

create table if not exists public.fuel_price_reports (
  id                 uuid primary key default gen_random_uuid(),
  poi_place_id        uuid references public.poi_places(id) on delete set null,
  driver_id           uuid,
  company_id          uuid,
  latitude            double precision check (latitude between -90 and 90),
  longitude           double precision check (longitude between -180 and 180),
  station_name        text,
  network             text,
  diesel_price_usd    numeric(8, 3) not null check (diesel_price_usd > 0),
  gallons             numeric(8, 3) check (gallons is null or gallons > 0),
  total_usd           numeric(10, 2) check (total_usd is null or total_usd > 0),
  evidence_type       text not null default 'manual'
    check (evidence_type in ('manual', 'receipt_photo', 'price_sign_photo', 'partner_feed')),
  evidence_storage_path text,
  confidence_score    numeric(4, 3) not null default 0.500
    check (confidence_score >= 0 and confidence_score <= 1),
  reported_at         timestamptz not null default now(),
  created_at          timestamptz not null default now()
);

create index if not exists idx_fuel_price_reports_place_time
  on public.fuel_price_reports (poi_place_id, reported_at desc)
  where poi_place_id is not null;

create index if not exists idx_fuel_price_reports_driver_time
  on public.fuel_price_reports (driver_id, reported_at desc)
  where driver_id is not null;

create index if not exists idx_fuel_price_reports_geo_time
  on public.fuel_price_reports (reported_at desc, latitude, longitude);

-- Private OCR/extraction record. Keep raw receipt metadata separate from public price data.
create table if not exists public.fuel_receipts (
  id                 uuid primary key default gen_random_uuid(),
  fuel_price_report_id uuid references public.fuel_price_reports(id) on delete cascade,
  driver_id           uuid,
  company_id          uuid,
  storage_path        text not null,
  ocr_status          text not null default 'pending'
    check (ocr_status in ('pending', 'processed', 'failed', 'redacted')),
  ocr_payload         jsonb not null default '{}'::jsonb,
  redaction_notes     text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists idx_fuel_receipts_driver_time
  on public.fuel_receipts (driver_id, created_at desc)
  where driver_id is not null;

create or replace function public.set_fuel_receipts_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_fuel_receipts_updated_at on public.fuel_receipts;
create trigger trg_fuel_receipts_updated_at
  before update on public.fuel_receipts
  for each row
  execute function public.set_fuel_receipts_updated_at();

alter table public.fuel_price_reports enable row level security;
alter table public.fuel_receipts enable row level security;

drop policy if exists fuel_price_reports_insert_authenticated on public.fuel_price_reports;
create policy fuel_price_reports_insert_authenticated
  on public.fuel_price_reports
  for insert
  to authenticated
  with check (driver_id = auth.uid());

drop policy if exists fuel_price_reports_select_own on public.fuel_price_reports;
create policy fuel_price_reports_select_own
  on public.fuel_price_reports
  for select
  to authenticated
  using (driver_id = auth.uid());

drop policy if exists fuel_receipts_insert_authenticated on public.fuel_receipts;
create policy fuel_receipts_insert_authenticated
  on public.fuel_receipts
  for insert
  to authenticated
  with check (driver_id = auth.uid());

drop policy if exists fuel_receipts_select_own on public.fuel_receipts;
create policy fuel_receipts_select_own
  on public.fuel_receipts
  for select
  to authenticated
  using (driver_id = auth.uid());

-- Optional private bucket for receipt/sign photos. Policies for storage.objects
-- should be tightened per company/driver before production rollout.
insert into storage.buckets (id, name, public)
values ('fuel-receipts', 'fuel-receipts', false)
on conflict (id) do nothing;

drop policy if exists fuel_receipts_storage_insert_own on storage.objects;
create policy fuel_receipts_storage_insert_own
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'fuel-receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'heic', 'pdf')
  );

drop policy if exists fuel_receipts_storage_select_own on storage.objects;
create policy fuel_receipts_storage_select_own
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'fuel-receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists fuel_receipts_storage_update_own on storage.objects;
create policy fuel_receipts_storage_update_own
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'fuel-receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'fuel-receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
    and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'heic', 'pdf')
  );
