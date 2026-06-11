-- Remove duplicate truck_stop rows from OSM ingest (same name + ~11 m). Keeps richest row per cluster.

with ranked as (
  select
    id,
    row_number() over (
      partition by
        poi_type,
        lower(coalesce(network, brand, name, '')),
        round(lat::numeric, 3),
        round(lon::numeric, 3)
      order by
        case when poi_type = 'truck_stop' then 0 else 1 end,
        case when source = 'osm_pbf' then 0 else 1 end,
        updated_at desc nulls last,
        id
    ) as rn
  from public.poi_places
  where poi_type in ('truck_stop', 'fuel')
)
delete from public.poi_places p
using ranked r
where p.id = r.id
  and r.rn > 1;
