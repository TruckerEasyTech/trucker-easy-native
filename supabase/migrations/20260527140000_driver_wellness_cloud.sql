-- Daily driver wellness check-ins + visit/mood correlation insights (ops + fleet intelligence).

create table if not exists public.driver_wellness_checkins (
  id              uuid primary key default gen_random_uuid(),
  driver_id       uuid not null,
  checkin_date    date not null,
  mood_stars      integer check (mood_stars is null or (mood_stars between 1 and 5)),
  stress_level    integer check (stress_level is null or (stress_level between 1 and 5)),
  sleep_hours     numeric(4, 1) check (sleep_hours is null or (sleep_hours between 0 and 24)),
  had_meal        boolean,
  felt_rested     boolean,
  source          text not null default 'launch'
    check (source in ('launch', 'checkup', 'horizon')),
  reported_at     timestamptz not null default now(),
  created_at      timestamptz not null default now()
);

create unique index if not exists idx_driver_wellness_checkins_driver_day
  on public.driver_wellness_checkins (driver_id, checkin_date);

create index if not exists idx_driver_wellness_checkins_reported
  on public.driver_wellness_checkins (reported_at desc);

create table if not exists public.driver_wellness_insights (
  id                       uuid primary key default gen_random_uuid(),
  driver_id                uuid not null,
  visit_kind               text not null
    check (visit_kind in ('truck_stop', 'pickup', 'delivery')),
  place_name               text not null,
  mood_stars               integer check (mood_stars is null or (mood_stars between 1 and 5)),
  visit_avg_stars          numeric(3, 2) check (visit_avg_stars is null or (visit_avg_stars between 1 and 5)),
  service_rating           integer check (service_rating is null or (service_rating between 1 and 5)),
  shower_rating            integer check (shower_rating is null or (shower_rating between 1 and 5)),
  food_rating              integer check (food_rating is null or (food_rating between 1 and 5)),
  treatment_rating         integer check (treatment_rating is null or (treatment_rating between 1 and 5)),
  bathroom_rating          integer check (bathroom_rating is null or (bathroom_rating between 1 and 5)),
  food_access_rating       integer check (food_access_rating is null or (food_access_rating between 1 and 5)),
  access_rating            integer check (access_rating is null or (access_rating between 1 and 5)),
  correlation_note         text,
  latitude                 double precision check (latitude is null or (latitude between -90 and 90)),
  longitude                double precision check (longitude is null or (longitude between -180 and 180)),
  load_number              text,
  company_name             text,
  reported_at              timestamptz not null default now(),
  created_at               timestamptz not null default now()
);

create index if not exists idx_driver_wellness_insights_driver_time
  on public.driver_wellness_insights (driver_id, reported_at desc);

create index if not exists idx_driver_wellness_insights_place_time
  on public.driver_wellness_insights (place_name, reported_at desc);

create or replace view public.driver_wellness_daily_summary
with (security_invoker = true)
as
select
  c.checkin_date,
  count(distinct c.driver_id)::integer as drivers_checked_in,
  round(avg(c.mood_stars)::numeric, 2) as avg_mood_stars,
  round(avg(c.sleep_hours)::numeric, 2) as avg_sleep_hours,
  count(*) filter (where c.had_meal)::integer as drivers_with_meal,
  count(*) filter (where c.felt_rested)::integer as drivers_felt_rested
from public.driver_wellness_checkins c
where c.mood_stars is not null
group by c.checkin_date
order by c.checkin_date desc;

alter table public.driver_wellness_checkins enable row level security;
alter table public.driver_wellness_insights enable row level security;

drop policy if exists driver_wellness_checkins_insert_own on public.driver_wellness_checkins;
create policy driver_wellness_checkins_insert_own
  on public.driver_wellness_checkins
  for insert
  to authenticated
  with check (driver_id = auth.uid());

drop policy if exists driver_wellness_checkins_update_own on public.driver_wellness_checkins;
create policy driver_wellness_checkins_update_own
  on public.driver_wellness_checkins
  for update
  to authenticated
  using (driver_id = auth.uid())
  with check (driver_id = auth.uid());

drop policy if exists driver_wellness_checkins_select_own on public.driver_wellness_checkins;
create policy driver_wellness_checkins_select_own
  on public.driver_wellness_checkins
  for select
  to authenticated
  using (driver_id = auth.uid());

drop policy if exists driver_wellness_checkins_service_all on public.driver_wellness_checkins;
create policy driver_wellness_checkins_service_all
  on public.driver_wellness_checkins
  for all
  to service_role
  using (true)
  with check (true);

drop policy if exists driver_wellness_insights_insert_own on public.driver_wellness_insights;
create policy driver_wellness_insights_insert_own
  on public.driver_wellness_insights
  for insert
  to authenticated
  with check (driver_id = auth.uid());

drop policy if exists driver_wellness_insights_select_own on public.driver_wellness_insights;
create policy driver_wellness_insights_select_own
  on public.driver_wellness_insights
  for select
  to authenticated
  using (driver_id = auth.uid());

drop policy if exists driver_wellness_insights_service_all on public.driver_wellness_insights;
create policy driver_wellness_insights_service_all
  on public.driver_wellness_insights
  for all
  to service_role
  using (true)
  with check (true);
