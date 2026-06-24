alter table public.communities
  add column if not exists owner_only_messages boolean not null default false;

alter table public.community_messages
  add column if not exists reply_to_message_id uuid
    references public.community_messages(id) on delete set null,
  add column if not exists route_attachment jsonb;

create index if not exists idx_community_messages_reply_to
  on public.community_messages (reply_to_message_id);

alter table public.communities
  drop constraint if exists communities_invite_code_format;

alter table public.communities
  add constraint communities_invite_code_format
  check (
    invite_code is null
    or invite_code ~ '^CCC-[A-Z2-9]{6}$'
    or invite_code ~ '^CM-[A-Z2-9]{6}$'
  );

create or replace function public.generate_community_invite_code()
returns text
language plpgsql
set search_path = public
as $$
declare
  alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  code text;
  tries int := 0;
begin
  loop
    code := 'CCC-' || (
      select string_agg(substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1), '')
      from generate_series(1, 6)
    );
    exit when not exists (
      select 1 from public.communities c where upper(c.invite_code) = upper(code)
    );
    tries := tries + 1;
    if tries > 10 then
      raise exception 'could not generate unique community invite_code after 10 tries';
    end if;
  end loop;
  return code;
end;
$$;

create or replace function public.normalize_community_invite_code(p_code text)
returns text
language sql
immutable
set search_path = public
as $$
  with cleaned as (
    select regexp_replace(upper(coalesce(p_code, '')), '[^A-Z0-9]', '', 'g') as value
  )
  select case
    when value ~ '^CCC[A-Z2-9]{6}$' then 'CCC-' || substring(value from 4)
    when value ~ '^CM[A-Z2-9]{6}$' then 'CM-' || substring(value from 3)
    else null
  end
  from cleaned;
$$;

drop policy if exists "members_write_community_messages"
  on public.community_messages;
create policy "members_write_community_messages"
  on public.community_messages for insert
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.community_members cm
      join public.communities c on c.id = cm.community_id
      where cm.community_id = community_messages.community_id
        and cm.user_id = auth.uid()
        and (
          coalesce(c.owner_only_messages, false) = false
          or cm.role in ('owner', 'moderator')
        )
    )
  );

drop policy if exists "authors_update_community_messages"
  on public.community_messages;
create policy "authors_update_community_messages"
  on public.community_messages for update
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.community_members cm
      where cm.community_id = community_messages.community_id
        and cm.user_id = auth.uid()
        and cm.role in ('owner', 'moderator')
    )
  )
  with check (
    user_id = auth.uid()
    or exists (
      select 1
      from public.community_members cm
      where cm.community_id = community_messages.community_id
        and cm.user_id = auth.uid()
        and cm.role in ('owner', 'moderator')
    )
  );

alter table public.group_members
  alter column ride_role set default 'driver';

create or replace function public.join_group_with_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_group public.groups%rowtype;
  v_uid uuid;
  v_member_count integer;
  v_already_member boolean;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Bitte melde dich an.';
  end if;

  v_code := public.normalize_group_invite_code(p_code);
  if v_code is null then
    raise exception 'Code ungueltig.';
  end if;

  select * into v_group
  from public.groups
  where upper(invite_code) = upper(v_code)
  for update;

  if not found then
    raise exception 'Code ungueltig.';
  end if;

  if coalesce(v_group.is_active, false) = true
     or v_group.activated_at is not null then
    raise exception 'Die Session laeuft bereits oder wurde schon beendet.';
  end if;

  select exists (
    select 1
    from public.group_members gm
    where gm.group_id = v_group.id
      and gm.user_id = v_uid
  )
  into v_already_member;

  if v_already_member then
    return v_group.id;
  end if;

  select count(*) into v_member_count
  from public.group_members gm
  where gm.group_id = v_group.id;

  if v_member_count >= v_group.max_people then
    raise exception 'Gruppe voll.';
  end if;

  insert into public.group_members (group_id, user_id, role, ride_role)
  values (v_group.id, v_uid, 'passenger', 'driver')
  on conflict (group_id, user_id) do nothing;

  return v_group.id;
end;
$$;

grant execute on function public.normalize_community_invite_code(text)
  to authenticated;
grant execute on function public.join_group_with_code(text)
  to anon, authenticated;
