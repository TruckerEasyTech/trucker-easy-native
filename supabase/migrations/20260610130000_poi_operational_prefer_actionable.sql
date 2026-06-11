-- Prefer open/closed weigh_status over static "monitoring" when both exist for the same POI.

create or replace view public.poi_operational_latest
with (security_invoker = true)
as
select distinct on (poi_place_id, signal_type)
  poi_place_id,
  signal_type,
  status_value,
  available_slots,
  total_slots,
  source,
  source_url,
  confidence_score,
  observed_at
from public.poi_operational_status
order by
  poi_place_id,
  signal_type,
  case
    when signal_type = 'weigh_status'
      and lower(status_value) in ('open', 'closed') then 0
    when signal_type = 'site_open'
      and lower(status_value) in ('open', 'closed') then 0
    else 1
  end,
  observed_at desc;
