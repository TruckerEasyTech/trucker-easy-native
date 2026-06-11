-- Driver facility reviews (pickup / delivery companies) — crowd intelligence for shipper treatment.

create table if not exists public.shipper_facility_reviews (
  id                  uuid primary key default gen_random_uuid(),
  driver_id           uuid,
  load_number         text not null,
  company_id          text,
  company_name        text,
  review_type         text not null check (review_type in ('pickup', 'delivery')),
  latitude            double precision not null check (latitude between -90 and 90),
  longitude           double precision not null check (longitude between -180 and 180),
  treatment_rating    integer check (treatment_rating between 1 and 5),
  bathroom_rating     integer check (bathroom_rating between 1 and 5),
  food_access_rating  integer check (food_access_rating between 1 and 5),
  access_rating       integer check (access_rating between 1 and 5),
  wait_minutes        integer check (wait_minutes is null or wait_minutes >= 0),
  overall_rating      numeric(3, 2) not null check (overall_rating >= 1 and overall_rating <= 5),
  notes               text,
  reported_at         timestamptz not null default now(),
  created_at          timestamptz not null default now()
);

create index if not exists idx_shipper_facility_reviews_company_time
  on public.shipper_facility_reviews (company_name, reported_at desc)
  where company_name is not null;

create index if not exists idx_shipper_facility_reviews_geo_time
  on public.shipper_facility_reviews (reported_at desc, latitude, longitude);

create index if not exists idx_shipper_facility_reviews_driver_time
  on public.shipper_facility_reviews (driver_id, reported_at desc)
  where driver_id is not null;

create or replace view public.shipper_facility_review_summaries
with (security_invoker = true)
as
select
  coalesce(company_name, load_number) as facility_key,
  company_name,
  count(*)::integer as review_count,
  round(avg(overall_rating)::numeric, 2) as rating,
  round(avg(treatment_rating)::numeric, 2) as avg_treatment,
  round(avg(bathroom_rating)::numeric, 2) as avg_bathroom,
  round(avg(food_access_rating)::numeric, 2) as avg_food_access,
  max(reported_at) as last_review_at
from public.shipper_facility_reviews
group by coalesce(company_name, load_number), company_name;

alter table public.shipper_facility_reviews enable row level security;

drop policy if exists shipper_facility_reviews_insert_own on public.shipper_facility_reviews;
create policy shipper_facility_reviews_insert_own
  on public.shipper_facility_reviews
  for insert
  to authenticated
  with check (driver_id = auth.uid());

drop policy if exists shipper_facility_reviews_select_public on public.shipper_facility_reviews;
create policy shipper_facility_reviews_select_public
  on public.shipper_facility_reviews
  for select
  to anon, authenticated
  using (true);

drop policy if exists shipper_facility_reviews_service_all on public.shipper_facility_reviews;
create policy shipper_facility_reviews_service_all
  on public.shipper_facility_reviews
  for all
  to service_role
  using (true)
  with check (true);
