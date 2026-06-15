-- Lets an authenticated user delete their own account without exposing a
-- service-role key in the app.

drop policy if exists "car_images_owner_delete" on storage.objects;
create policy "car_images_owner_delete"
  on storage.objects for delete
  using (
    bucket_id = 'car_images'
    and auth.role() = 'authenticated'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "banners_owner_delete" on storage.objects;
create policy "banners_owner_delete"
  on storage.objects for delete
  using (
    bucket_id = 'banners'
    and auth.role() = 'authenticated'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create or replace function public.delete_current_user()
returns void
language plpgsql
security definer
set search_path = public, auth, storage
as $$
declare
  target_user_id uuid := auth.uid();
  cleanup record;
  fk_cleanup record;
  relation_oid regclass;
begin
  if target_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  for cleanup in
    select * from (values
      ('public.comment_likes', 'user_id', 'delete'),
      ('public.post_likes', 'user_id', 'delete'),
      ('public.reposts', 'user_id', 'delete'),
      ('public.comments', 'user_id', 'delete'),
      ('public.content_reports', 'reporter_id', 'delete'),
      ('public.content_reports', 'reported_user_id', 'null'),
      ('public.content_reports', 'reviewed_by', 'null'),
      ('public.posts', 'user_id', 'delete'),
      ('public.route_bookmarks', 'user_id', 'delete'),
      ('public.route_ratings', 'user_id', 'delete'),
      ('public.user_drive_sessions', 'user_id', 'delete'),
      ('public.user_device_tokens', 'user_id', 'delete'),
      ('public.trips', 'owner_id', 'delete'),
      ('public.profile_vehicles', 'user_id', 'delete'),
      ('public.follow_requests', 'follower_id', 'delete'),
      ('public.follow_requests', 'following_id', 'delete'),
      ('public.follows', 'follower_id', 'delete'),
      ('public.follows', 'following_id', 'delete'),
      ('public.notifications', 'user_id', 'delete'),
      ('public.notifications', 'from_user_id', 'delete'),
      ('public.user_blocks', 'blocker_id', 'delete'),
      ('public.user_blocks', 'blocked_id', 'delete'),
      ('public.community_messages', 'user_id', 'delete'),
      ('public.community_join_requests', 'user_id', 'delete'),
      ('public.community_members', 'user_id', 'delete'),
      ('public.communities', 'owner_id', 'delete'),
      ('public.group_join_requests', 'user_id', 'delete'),
      ('public.group_members', 'added_by', 'null'),
      ('public.group_members', 'user_id', 'delete'),
      ('public.groups', 'created_by', 'delete'),
      ('public.routes', 'route_updated_by', 'null'),
      ('public.routes', 'user_id', 'delete'),
      ('public.route_search_sessions', 'user_id', 'delete'),
      ('public.pool_demand_log', 'user_id', 'null')
    ) as c(relation_name, column_name, cleanup_action)
  loop
    relation_oid := to_regclass(cleanup.relation_name);
    if relation_oid is not null
       and exists (
         select 1
           from pg_attribute
          where attrelid = relation_oid
            and attname = cleanup.column_name
            and not attisdropped
       ) then
      if cleanup.cleanup_action = 'delete' then
        execute format(
          'delete from %s where %I = $1',
          relation_oid,
          cleanup.column_name
        ) using target_user_id;
      else
        execute format(
          'update %s set %I = null where %I = $1',
          relation_oid,
          cleanup.column_name,
          cleanup.column_name
        ) using target_user_id;
      end if;
    end if;
  end loop;

  -- Catch future direct user/profile foreign keys that are not in the explicit
  -- ownership cleanup above. SET NULL constraints keep their row; all other
  -- direct user/profile rows are deleted.
  for fk_cleanup in
    select
      con.conname,
      con.confdeltype,
      con.conrelid as relation_oid,
      quote_ident(nsp.nspname) || '.' || quote_ident(cls.relname) as relation_name,
      att.attname as column_name,
      att.attnotnull
    from pg_constraint con
    join pg_class cls on cls.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = cls.relnamespace
    join pg_attribute att
      on att.attrelid = con.conrelid
     and att.attnum = con.conkey[1]
    where con.contype = 'f'
      and nsp.nspname = 'public'
      and array_length(con.conkey, 1) = 1
      and con.confrelid in ('auth.users'::regclass, 'public.profiles'::regclass)
    order by
      case when con.conrelid = 'public.profiles'::regclass then 1 else 0 end,
      nsp.nspname,
      cls.relname,
      att.attname
  loop
    if fk_cleanup.confdeltype = 'n' and not fk_cleanup.attnotnull then
      execute format(
        'update %s set %I = null where %I = $1',
        fk_cleanup.relation_name,
        fk_cleanup.column_name,
        fk_cleanup.column_name
      ) using target_user_id;
    else
      execute format(
        'delete from %s where %I = $1',
        fk_cleanup.relation_name,
        fk_cleanup.column_name
      ) using target_user_id;
    end if;
  end loop;

  -- Safety net for files uploaded under <uid>/... in public buckets. Storage
  -- cleanup must never block account deletion.
  begin
    delete from storage.objects
     where bucket_id in ('avatars', 'banners', 'car_images')
       and (
         name = target_user_id::text
         or name like target_user_id::text || '/%'
       );
  exception
    when others then
      raise warning 'delete_current_user storage cleanup failed for %: %',
        target_user_id,
        sqlerrm;
  end;

  delete from auth.users where id = target_user_id;
  if not found then
    raise exception 'user_not_found' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.delete_current_user() from public;
revoke all on function public.delete_current_user() from anon;
grant execute on function public.delete_current_user() to authenticated;
