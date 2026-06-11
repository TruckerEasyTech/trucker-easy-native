-- Enable Supabase Realtime for ops dashboard tables (Lovable /ops).

alter table if exists public.health_checks replica identity full;
alter table if exists public.notifications replica identity full;
alter table if exists public.usage_metrics replica identity full;

do $$
begin
  alter publication supabase_realtime add table public.health_checks;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.notifications;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.usage_metrics;
exception
  when duplicate_object then null;
end $$;
