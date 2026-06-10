-- Separate chat communities. Do not mix these with public.groups, which are
-- ride/group-drive lobbies with routes and start times.

do $$ begin
  create type public.community_member_role as enum ('owner', 'moderator', 'member');
exception when duplicate_object then null; end $$;

create table if not exists public.communities (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  description text,
  is_public boolean not null default true,
  invite_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communities_name_length check (char_length(name) between 1 and 40),
  constraint communities_description_length check (
    description is null or char_length(description) <= 300
  ),
  constraint communities_invite_code_format check (
    invite_code is null or invite_code ~ '^CM-[A-Z2-9]{6}$'
  )
);

create unique index if not exists communities_invite_code_key
  on public.communities (upper(invite_code));
create index if not exists communities_public_created_idx
  on public.communities (is_public, created_at desc);

create table if not exists public.community_members (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.community_member_role not null default 'member',
  created_at timestamptz not null default now(),
  unique (community_id, user_id)
);

create index if not exists community_members_user_idx
  on public.community_members (user_id, created_at desc);
create index if not exists community_members_community_idx
  on public.community_members (community_id, role);

create table if not exists public.community_messages (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  deleted_at timestamptz,
  constraint community_messages_body_length check (
    char_length(trim(body)) between 1 and 2000
  )
);

create index if not exists community_messages_community_created_idx
  on public.community_messages (community_id, created_at desc);

create table if not exists public.community_join_requests (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected')),
  message text,
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  unique (community_id, user_id),
  constraint community_join_requests_message_length check (
    message is null or char_length(message) <= 300
  )
);

create index if not exists community_join_requests_owner_idx
  on public.community_join_requests (community_id, status, created_at);
create index if not exists community_join_requests_user_idx
  on public.community_join_requests (user_id, status, created_at desc);

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
    code := 'CM-' || (
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

create or replace function public.set_community_defaults_on_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.invite_code is null or new.invite_code = '' then
    new.invite_code := public.generate_community_invite_code();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_community_defaults on public.communities;
create trigger trg_community_defaults
  before insert on public.communities
  for each row execute function public.set_community_defaults_on_insert();

create or replace function public.set_community_owner_member_on_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.community_members (community_id, user_id, role)
  values (new.id, new.owner_id, 'owner')
  on conflict (community_id, user_id) do update set role = 'owner';
  return new;
end;
$$;

drop trigger if exists trg_community_owner_member on public.communities;
create trigger trg_community_owner_member
  after insert on public.communities
  for each row execute function public.set_community_owner_member_on_insert();

create or replace function public.touch_community_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_communities_touch_updated_at on public.communities;
create trigger trg_communities_touch_updated_at
  before update on public.communities
  for each row execute function public.touch_community_updated_at();

create or replace function public.is_community_member(
  p_community_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_user_id is not null
    and exists (
      select 1
      from public.community_members cm
      where cm.community_id = p_community_id
        and cm.user_id = p_user_id
    );
$$;

create or replace function public.is_community_owner(
  p_community_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_user_id is not null
    and exists (
      select 1
      from public.community_members cm
      where cm.community_id = p_community_id
        and cm.user_id = p_user_id
        and cm.role in ('owner', 'moderator')
    );
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
    when value ~ '^CM[A-Z2-9]{6}$' then 'CM-' || substring(value from 3)
    else null
  end
  from cleaned;
$$;

create or replace function public.find_community_by_code(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_code text;
  v_community public.communities%rowtype;
  v_member_count integer;
  v_owner jsonb;
begin
  v_code := public.normalize_community_invite_code(p_code);
  if v_code is null then
    return null;
  end if;

  select * into v_community
  from public.communities
  where upper(invite_code) = upper(v_code);

  if not found then
    return null;
  end if;

  select count(*) into v_member_count
  from public.community_members cm
  where cm.community_id = v_community.id;

  select jsonb_build_object(
    'id', p.id,
    'username', p.username,
    'avatar_url', p.avatar_url
  )
  into v_owner
  from public.profiles p
  where p.id = v_community.owner_id;

  return jsonb_build_object(
    'id', v_community.id,
    'owner_id', v_community.owner_id,
    'name', v_community.name,
    'description', v_community.description,
    'is_public', v_community.is_public,
    'invite_code', v_code,
    'created_at', v_community.created_at,
    'member_count', v_member_count,
    'owner_profile', v_owner
  );
end;
$$;

create or replace function public.join_community_with_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_community public.communities%rowtype;
  v_uid uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Bitte melde dich an.';
  end if;

  v_code := public.normalize_community_invite_code(p_code);
  if v_code is null then
    raise exception 'Code ungueltig.';
  end if;

  select * into v_community
  from public.communities
  where upper(invite_code) = upper(v_code);

  if not found then
    raise exception 'Code ungueltig.';
  end if;

  insert into public.community_members (community_id, user_id, role)
  values (v_community.id, v_uid, 'member')
  on conflict (community_id, user_id) do nothing;

  return v_community.id;
end;
$$;

create or replace function public.accept_community_join_request(req_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  rec public.community_join_requests%rowtype;
begin
  select * into rec
  from public.community_join_requests
  where id = req_id
  for update;

  if not found then raise exception 'request not found'; end if;
  if rec.status <> 'pending' then raise exception 'request is not pending'; end if;
  if not public.is_community_owner(rec.community_id, auth.uid()) then
    raise exception 'only community leaders may accept requests';
  end if;

  insert into public.community_members (community_id, user_id, role)
  values (rec.community_id, rec.user_id, 'member')
  on conflict (community_id, user_id) do nothing;

  update public.community_join_requests
     set status = 'accepted', responded_at = now()
   where id = req_id;
end;
$$;

create or replace function public.reject_community_join_request(req_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  rec public.community_join_requests%rowtype;
begin
  select * into rec
  from public.community_join_requests
  where id = req_id
  for update;

  if not found then raise exception 'request not found'; end if;
  if not public.is_community_owner(rec.community_id, auth.uid()) then
    raise exception 'only community leaders may reject requests';
  end if;

  update public.community_join_requests
     set status = 'rejected', responded_at = now()
   where id = req_id
     and status = 'pending';
end;
$$;

alter table public.communities enable row level security;
alter table public.community_members enable row level security;
alter table public.community_messages enable row level security;
alter table public.community_join_requests enable row level security;

drop policy if exists "communities_visible_public_or_member" on public.communities;
create policy "communities_visible_public_or_member"
  on public.communities for select
  using (
    coalesce(is_public, false) = true
    or public.is_community_member(id, auth.uid())
  );

drop policy if exists "users_create_own_communities" on public.communities;
create policy "users_create_own_communities"
  on public.communities for insert
  with check (owner_id = auth.uid());

drop policy if exists "leaders_update_communities" on public.communities;
create policy "leaders_update_communities"
  on public.communities for update
  using (public.is_community_owner(id, auth.uid()))
  with check (public.is_community_owner(id, auth.uid()));

drop policy if exists "leaders_delete_communities" on public.communities;
create policy "leaders_delete_communities"
  on public.communities for delete
  using (public.is_community_owner(id, auth.uid()));

drop policy if exists "community_members_visible_public_or_member" on public.community_members;
create policy "community_members_visible_public_or_member"
  on public.community_members for select
  using (
    exists (
      select 1 from public.communities c
      where c.id = community_members.community_id
        and coalesce(c.is_public, false) = true
    )
    or public.is_community_member(community_id, auth.uid())
  );

drop policy if exists "users_join_public_communities" on public.community_members;
create policy "users_join_public_communities"
  on public.community_members for insert
  with check (
    (
      user_id = auth.uid()
      and role = 'member'
      and exists (
        select 1 from public.communities c
        where c.id = community_members.community_id
          and coalesce(c.is_public, false) = true
      )
    )
    or public.is_community_owner(community_id, auth.uid())
  );

drop policy if exists "members_leave_or_leaders_remove" on public.community_members;
create policy "members_leave_or_leaders_remove"
  on public.community_members for delete
  using (
    user_id = auth.uid()
    or public.is_community_owner(community_id, auth.uid())
  );

drop policy if exists "leaders_update_community_members" on public.community_members;
create policy "leaders_update_community_members"
  on public.community_members for update
  using (public.is_community_owner(community_id, auth.uid()))
  with check (public.is_community_owner(community_id, auth.uid()));

drop policy if exists "members_read_community_messages" on public.community_messages;
create policy "members_read_community_messages"
  on public.community_messages for select
  using (public.is_community_member(community_id, auth.uid()));

drop policy if exists "members_write_community_messages" on public.community_messages;
create policy "members_write_community_messages"
  on public.community_messages for insert
  with check (
    user_id = auth.uid()
    and public.is_community_member(community_id, auth.uid())
  );

drop policy if exists "authors_update_community_messages" on public.community_messages;
create policy "authors_update_community_messages"
  on public.community_messages for update
  using (
    user_id = auth.uid()
    or public.is_community_owner(community_id, auth.uid())
  )
  with check (
    user_id = auth.uid()
    or public.is_community_owner(community_id, auth.uid())
  );

drop policy if exists "authors_delete_community_messages" on public.community_messages;
create policy "authors_delete_community_messages"
  on public.community_messages for delete
  using (
    user_id = auth.uid()
    or public.is_community_owner(community_id, auth.uid())
  );

drop policy if exists "community_join_requests_visible_to_user_or_leader" on public.community_join_requests;
create policy "community_join_requests_visible_to_user_or_leader"
  on public.community_join_requests for select
  using (
    user_id = auth.uid()
    or public.is_community_owner(community_id, auth.uid())
  );

drop policy if exists "users_request_private_community_join" on public.community_join_requests;
create policy "users_request_private_community_join"
  on public.community_join_requests for insert
  with check (
    user_id = auth.uid()
    and status = 'pending'
    and not public.is_community_member(community_id, auth.uid())
  );

drop policy if exists "users_cancel_community_join_request" on public.community_join_requests;
create policy "users_cancel_community_join_request"
  on public.community_join_requests for delete
  using (user_id = auth.uid());

drop policy if exists "leaders_update_community_join_requests" on public.community_join_requests;
create policy "leaders_update_community_join_requests"
  on public.community_join_requests for update
  using (public.is_community_owner(community_id, auth.uid()))
  with check (public.is_community_owner(community_id, auth.uid()));

grant select on public.communities to anon, authenticated;
grant insert, update, delete on public.communities to authenticated;
grant select on public.community_members to anon, authenticated;
grant insert, update, delete on public.community_members to authenticated;
grant select, insert, update, delete on public.community_messages to authenticated;
grant select, insert, update, delete on public.community_join_requests to authenticated;

revoke all on function public.is_community_member(uuid, uuid) from public;
revoke all on function public.is_community_owner(uuid, uuid) from public;
revoke all on function public.normalize_community_invite_code(text) from public;
revoke all on function public.find_community_by_code(text) from public;
revoke all on function public.join_community_with_code(text) from public;
revoke all on function public.accept_community_join_request(uuid) from public;
revoke all on function public.reject_community_join_request(uuid) from public;

grant execute on function public.is_community_member(uuid, uuid) to anon, authenticated;
grant execute on function public.is_community_owner(uuid, uuid) to anon, authenticated;
grant execute on function public.normalize_community_invite_code(text) to authenticated;
grant execute on function public.find_community_by_code(text) to authenticated;
grant execute on function public.join_community_with_code(text) to authenticated;
grant execute on function public.accept_community_join_request(uuid) to authenticated;
grant execute on function public.reject_community_join_request(uuid) to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.communities;
exception when duplicate_object or undefined_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.community_members;
exception when duplicate_object or undefined_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.community_messages;
exception when duplicate_object or undefined_object then null;
end $$;

notify pgrst, 'reload schema';
