-- Trucker Easy — operational dashboard schema (idempotent)
-- Aligns with: usage_metrics, health_checks, notifications, documentation,
-- truck_routing_config (config_key + environment), deployment_environments

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- deployment_environments
-- ---------------------------------------------------------------------------
create table if not exists deployment_environments (
  id                uuid primary key default gen_random_uuid(),
  environment_name  text not null unique,
  display_name      text,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now()
);

insert into deployment_environments (environment_name, display_name)
values
  ('production', 'Production'),
  ('staging', 'Staging'),
  ('development', 'Development')
on conflict (environment_name) do nothing;

-- ---------------------------------------------------------------------------
-- truck_routing_config — per environment (Valhalla URLs, flags, etc.)
-- ---------------------------------------------------------------------------
create table if not exists truck_routing_config (
  id           uuid primary key default gen_random_uuid(),
  config_key   text not null,
  config_value jsonb not null default '{}'::jsonb,
  environment  text not null default 'production',
  description  text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Drop legacy unique on config_key only (if present)
do $$
begin
  if exists (
    select 1 from pg_constraint
    where conrelid = 'public.truck_routing_config'::regclass
      and conname = 'truck_routing_config_config_key_key'
  ) then
    alter table truck_routing_config
      drop constraint truck_routing_config_config_key_key;
  end if;
exception
  when undefined_table then null;
end $$;

alter table truck_routing_config
  alter column environment set default 'production';

update truck_routing_config
set environment = 'production'
where environment is null or btrim(environment) = '';

alter table truck_routing_config
  alter column environment set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.truck_routing_config'::regclass
      and conname = 'truck_routing_config_environment_check'
  ) then
    alter table truck_routing_config
      add constraint truck_routing_config_environment_check
      check (environment in ('production', 'staging', 'development'));
  end if;
end $$;

create unique index if not exists idx_truck_routing_config_key_env
  on truck_routing_config (config_key, environment);

create index if not exists idx_truck_routing_config_environment
  on truck_routing_config (environment);

create index if not exists idx_truck_routing_config_updated_at
  on truck_routing_config (updated_at desc);

create or replace function public.set_truck_routing_config_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_truck_routing_config_updated_at on truck_routing_config;
create trigger trg_truck_routing_config_updated_at
  before update on truck_routing_config
  for each row
  execute function public.set_truck_routing_config_updated_at();

-- ---------------------------------------------------------------------------
-- usage_metrics (monitoring — NOT system_metrics)
-- ---------------------------------------------------------------------------
create table if not exists usage_metrics (
  id            uuid primary key default gen_random_uuid(),
  metric_name   text not null,
  metric_value  double precision not null,
  metric_unit   text,
  environment   text not null default 'production',
  source        text,
  metadata      jsonb not null default '{}'::jsonb,
  recorded_at   timestamptz not null default now()
);

create index if not exists idx_usage_metrics_recorded_at
  on usage_metrics (recorded_at desc);

create index if not exists idx_usage_metrics_name_env
  on usage_metrics (metric_name, environment);

-- ---------------------------------------------------------------------------
-- health_checks
-- ---------------------------------------------------------------------------
create table if not exists health_checks (
  id              uuid primary key default gen_random_uuid(),
  check_name      text not null,
  status          text not null default 'unknown',
  response_ms     integer,
  details         jsonb not null default '{}'::jsonb,
  environment_id  uuid references deployment_environments(id) on delete set null,
  checked_at      timestamptz not null default now()
);

create index if not exists idx_health_checks_checked_at
  on health_checks (checked_at desc);

-- ---------------------------------------------------------------------------
-- notifications (alerts UI — NOT alerts table)
-- ---------------------------------------------------------------------------
create table if not exists notifications (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  message    text,
  severity   text not null default 'info',
  is_read    boolean not null default false,
  source     text,
  metadata   jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_notifications_created_at
  on notifications (created_at desc);

create index if not exists idx_notifications_unread
  on notifications (is_read, created_at desc)
  where is_read = false;

-- ---------------------------------------------------------------------------
-- documentation
-- ---------------------------------------------------------------------------
create table if not exists documentation (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  slug         text unique,
  body         text,
  doc_type     text,
  tags         text[] default '{}',
  language     text not null default 'en',
  is_published boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists idx_documentation_published
  on documentation (is_published, updated_at desc);

create index if not exists idx_documentation_doc_type
  on documentation (doc_type)
  where is_published = true;

-- Seed example routing config (safe to re-run)
insert into truck_routing_config (config_key, config_value, environment, description)
values (
  'valhalla_primary_url',
  '{"url": "https://valhalla.yourdomain.com"}'::jsonb,
  'production',
  'Primary Valhalla HTTPS endpoint for truck costing'
)
on conflict (config_key, environment) do nothing;
