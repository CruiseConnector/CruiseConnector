-- Atomic post reaction toggles.
-- These functions make likes/reposts robust even when clients tap quickly or
-- multiple screens update the same post.

create or replace function public.toggle_post_like(post_id_param uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_uid uuid := auth.uid();
  is_active boolean;
  new_count integer;
begin
  if current_uid is null then
    raise exception 'not_authenticated';
  end if;

  if exists (
    select 1 from public.post_likes
    where post_id = post_id_param and user_id = current_uid
  ) then
    delete from public.post_likes
    where post_id = post_id_param and user_id = current_uid;

    is_active := false;
  else
    insert into public.post_likes (post_id, user_id)
    values (post_id_param, current_uid)
    on conflict (post_id, user_id) do nothing;

    is_active := true;
  end if;

  select count(*)::integer
    into new_count
    from public.post_likes
   where post_id = post_id_param;

  update public.posts
     set likes_count = new_count
   where id = post_id_param;

  return jsonb_build_object(
    'is_active', is_active,
    'count', coalesce(new_count, 0)
  );
end;
$$;

create or replace function public.toggle_post_repost(post_id_param uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_uid uuid := auth.uid();
  is_active boolean;
  new_count integer;
begin
  if current_uid is null then
    raise exception 'not_authenticated';
  end if;

  if exists (
    select 1 from public.reposts
    where post_id = post_id_param and user_id = current_uid
  ) then
    delete from public.reposts
    where post_id = post_id_param and user_id = current_uid;

    is_active := false;
  else
    insert into public.reposts (post_id, user_id)
    values (post_id_param, current_uid)
    on conflict (post_id, user_id) do nothing;

    is_active := true;
  end if;

  select count(*)::integer
    into new_count
    from public.reposts
   where post_id = post_id_param;

  update public.posts
     set reposts_count = new_count
   where id = post_id_param;

  return jsonb_build_object(
    'is_active', is_active,
    'count', coalesce(new_count, 0)
  );
end;
$$;

grant execute on function public.toggle_post_like(uuid) to authenticated;
grant execute on function public.toggle_post_repost(uuid) to authenticated;
