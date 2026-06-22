-- Live trip sharing (acompanhamento read-only estilo Life360).
--
-- O motorista compartilha um link; a família abre no navegador e VÊ a posição ao vivo.
-- NÃO é navegação: a família só observa. A escrita (start/update/stop) passa pela
-- Edge Function `trip-share` usando service role (bypassa RLS). A leitura pública é
-- SOMENTE de viagens ativas e não expiradas. O token é aleatório e inadivinhável.

create table if not exists public.live_trip_shares (
    token        text primary key,
    driver_name  text not null default 'Driver',
    origin_name  text,
    dest_name    text,
    latitude     double precision,
    longitude    double precision,
    heading      double precision,
    speed_mph    double precision,
    active       boolean not null default true,
    started_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now(),
    expires_at   timestamptz not null default (now() + interval '12 hours')
);

comment on table public.live_trip_shares is
    'Posição ao vivo compartilhada com a família (read-only). Escrita via Edge Function service role; leitura pública só de ativos e não expirados.';

create index if not exists live_trip_shares_active_idx
    on public.live_trip_shares (active, expires_at);

alter table public.live_trip_shares enable row level security;

-- Leitura pública (anon) SOMENTE de viagens ativas e ainda não expiradas.
-- Sem o token (PK) a família não acha a linha; a Edge Function filtra por token.
drop policy if exists "public read active shares" on public.live_trip_shares;
create policy "public read active shares"
    on public.live_trip_shares
    for select
    to anon
    using (active = true and expires_at > now());

-- Nenhuma policy de insert/update/delete para anon: TODA escrita passa pela
-- Edge Function com service role (bypassa RLS). anon nunca grava direto.
