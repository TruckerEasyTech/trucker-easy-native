-- Fix: OSM tags Pilot/Love's/TA as amenity=fuel only — promote to truck_stop for app + places_near.

update public.poi_places
set
  poi_type = 'truck_stop',
  has_shower = case
    when has_shower then true
    when network in ('pilot', 'loves', 'ta', 'petro', 'sapp') then true
    when brand ilike '%pilot%' or brand ilike '%love%' or brand ilike '%petro%' then true
    else has_shower
  end,
  updated_at = now()
where poi_type = 'fuel'
  and has_hgv_fuel = true
  and (
    network in ('pilot', 'loves', 'ta', 'petro', 'sapp')
    or brand ilike '%pilot%'
    or brand ilike '%love%'
    or brand ilike '%petro%'
    or brand ilike '%flying j%'
    or name ilike '%pilot%'
    or name ilike '%love%'
    or name ilike '%travel center%'
    or name ilike '%flying j%'
  );

create table if not exists public.poi_ingest_runs (
  id uuid primary key default gen_random_uuid(),
  source text not null,
  regions text,
  rows_upserted integer,
  status text not null check (status in ('started', 'success', 'failed')),
  error_message text,
  started_at timestamptz not null default now(),
  finished_at timestamptz
);

alter table public.poi_ingest_runs enable row level security;

drop policy if exists poi_ingest_runs_service on public.poi_ingest_runs;
create policy poi_ingest_runs_service on public.poi_ingest_runs for all to service_role using (true) with check (true);

drop policy if exists poi_ingest_runs_select_auth on public.poi_ingest_runs;
create policy poi_ingest_runs_select_auth on public.poi_ingest_runs for select to authenticated using (true);
