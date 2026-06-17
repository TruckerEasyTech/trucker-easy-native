-- Feed da comunidade (RoadTalk → Community). O app referencia community_posts/post_comments mas as
-- tabelas nunca foram criadas (feature ficava vazia/silenciosa). Colunas batem EXATAMENTE com
-- CommunityPostPayload/Record e PostCommentPayload/Record do app (ServicesSupabaseClient).
-- Leitura pública (conteúdo social), escrita só do autor autenticado. Aplicar via SQL Editor ou db push.

create table if not exists public.community_posts (
  id            uuid primary key default gen_random_uuid(),
  author_id     text,
  title         text not null,
  content       text not null,
  category      text,
  location      text,
  like_count    integer not null default 0,
  comment_count integer not null default 0,
  created_at    timestamptz not null default now()
);

create index if not exists idx_community_posts_created on public.community_posts (created_at desc);
create index if not exists idx_community_posts_category on public.community_posts (category);

create table if not exists public.post_comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.community_posts(id) on delete cascade,
  author_id  text,
  content    text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_post_comments_post on public.post_comments (post_id, created_at);

alter table public.community_posts enable row level security;
alter table public.post_comments  enable row level security;

-- Leitura: conteúdo social é público (anon + autenticado podem ver o feed).
drop policy if exists community_posts_read on public.community_posts;
create policy community_posts_read on public.community_posts for select to anon, authenticated using (true);

drop policy if exists post_comments_read on public.post_comments;
create policy post_comments_read on public.post_comments for select to anon, authenticated using (true);

-- Escrita: só usuário autenticado, e só como ele mesmo (author_id = uid). Anti-spam/anti-falsa-autoria.
drop policy if exists community_posts_insert_own on public.community_posts;
create policy community_posts_insert_own on public.community_posts for insert to authenticated
  with check (author_id is null or author_id = auth.uid()::text);

drop policy if exists post_comments_insert_own on public.post_comments;
create policy post_comments_insert_own on public.post_comments for insert to authenticated
  with check (author_id is null or author_id = auth.uid()::text);

-- Update/delete só do próprio autor.
drop policy if exists community_posts_modify_own on public.community_posts;
create policy community_posts_modify_own on public.community_posts for update to authenticated
  using (author_id = auth.uid()::text) with check (author_id = auth.uid()::text);

drop policy if exists community_posts_delete_own on public.community_posts;
create policy community_posts_delete_own on public.community_posts for delete to authenticated
  using (author_id = auth.uid()::text);

grant select on public.community_posts, public.post_comments to anon, authenticated;
grant insert, update, delete on public.community_posts, public.post_comments to authenticated;
