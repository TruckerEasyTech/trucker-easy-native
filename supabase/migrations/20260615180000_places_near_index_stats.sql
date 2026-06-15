-- places_near performance fix: garante índice espacial + atualiza estatísticas do planner.
--
-- Sintoma: places_near com raio 20-40km levava 6-16s para poucas linhas (estourava o timeout
-- de 15s do app → caía no MapKit → truck stops não apareciam).
--
-- Causa: o índice gist(geom) JÁ existe e os tipos batem (geom é geography), mas o planner fazia
-- SEQ SCAN nas 22k linhas em vez de usar o índice — clássico de ESTATÍSTICAS DESATUALIZADAS após
-- carga em massa (poi_places ingerido por bulk sem ANALYZE). Sem stats, o custo do gist parece
-- alto e o planner varre tudo.
--
-- Esta migração é idempotente e segura: garante o índice e roda ANALYZE (que dá ao planner os
-- números reais → ele passa a usar o índice → st_dwithin/st_distance caem para ~ms).

-- 1) Garante o índice espacial (geography gist) — no-op se já existir.
create index if not exists idx_poi_places_geom
  on public.poi_places using gist (geom);

-- 2) Garante o índice de filtro por tipo (usado junto com o espacial em places_near).
create index if not exists idx_poi_places_poi_type
  on public.poi_places (poi_type);

-- 3) A CURA: atualiza as estatísticas para o planner escolher o índice em vez de seq scan.
analyze public.poi_places;

-- Nota operacional: aplicar com `supabase db push`. Produção está atrás nos migrations
-- (a tabela poi_signage do migration 20260613120000 ainda não existe em prod) — o push também
-- aplica a função places_near OTIMIZADA (20260610120000, KNN + join só nos candidatos limitados)
-- e a tabela de semáforos. Depois do push, validar:
--   select * from public.places_near(33.749, -84.388, 40233,
--     array['truck_stop','fuel','weigh_station','rest_area'], 30);
-- Esperado: retorno em < 1s (antes ~16s).
