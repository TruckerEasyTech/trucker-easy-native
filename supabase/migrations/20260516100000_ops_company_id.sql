-- company_id em tabelas ops (alinhado ao RLS por empresa no Lovable)

alter table if exists truck_routing_config
  add column if not exists company_id uuid;

alter table if exists health_checks
  add column if not exists company_id uuid;

alter table if exists usage_metrics
  add column if not exists company_id uuid;

alter table if exists notifications
  add column if not exists company_id uuid;

-- Unicidade: global (sem company) vs por empresa
drop index if exists idx_truck_routing_config_key_env;
create unique index if not exists idx_truck_routing_config_key_env_global
  on truck_routing_config (config_key, environment)
  where company_id is null;
create unique index if not exists idx_truck_routing_config_key_env_company
  on truck_routing_config (config_key, environment, company_id)
  where company_id is not null;

create index if not exists idx_health_checks_company_checked
  on health_checks (company_id, checked_at desc)
  where company_id is not null;

create index if not exists idx_usage_metrics_company_recorded
  on usage_metrics (company_id, recorded_at desc)
  where company_id is not null;
