-- Allow anonymous crowd weigh-station reports (Trucker Path style) and keep read open.
grant insert on public.weigh_station_reports to anon;

drop policy if exists anon_insert_weigh_station_reports on public.weigh_station_reports;
create policy anon_insert_weigh_station_reports
  on public.weigh_station_reports
  for insert
  to anon
  with check (true);
