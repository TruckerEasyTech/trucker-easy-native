-- Mantém community_posts.comment_count em sincronia com post_comments (insert/delete).
-- Sem isto a coluna fica congelada em 0 e o app mostra contagem errada. Idempotente (rerun-safe).

create or replace function public.sync_post_comment_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (tg_op = 'INSERT') then
    update public.community_posts
       set comment_count = comment_count + 1
     where id = new.post_id;
    return new;
  elsif (tg_op = 'DELETE') then
    update public.community_posts
       set comment_count = greatest(comment_count - 1, 0)
     where id = old.post_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_sync_post_comment_count on public.post_comments;
create trigger trg_sync_post_comment_count
  after insert or delete on public.post_comments
  for each row execute function public.sync_post_comment_count();

-- Reconcilia qualquer contagem existente (caso já haja comentários).
update public.community_posts p
   set comment_count = coalesce((select count(*) from public.post_comments c where c.post_id = p.id), 0);
