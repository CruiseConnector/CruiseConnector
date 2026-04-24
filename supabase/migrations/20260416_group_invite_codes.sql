-- =============================================================================
-- Gruppen-Codes + Join-Requests
-- =============================================================================
-- 1) invite_code auf groups (Format 'CC-XXXXXX', case-insensitive unique)
-- 2) Auto-Generierung via Trigger (mit Kollisions-Retry)
-- 3) Backfill für bestehende Gruppen
-- 4) group_join_requests Tabelle mit RLS
-- =============================================================================

-- 1) Spalte + Index --------------------------------------------------------
alter table groups add column if not exists invite_code text;

create unique index if not exists groups_invite_code_key
  on groups (upper(invite_code));

-- 2) Generator --------------------------------------------------------------
-- Zeichensatz ohne Verwechsler (0/O, 1/I/L)
create or replace function public.generate_group_invite_code()
returns text language plpgsql as $$
declare
  alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  code     text;
  tries    int  := 0;
begin
  loop
    code := 'CC-' || (
      select string_agg(substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1), '')
      from generate_series(1, 6)
    );
    exit when not exists (select 1 from groups where upper(invite_code) = upper(code));
    tries := tries + 1;
    if tries > 10 then
      raise exception 'could not generate unique group invite_code after 10 tries';
    end if;
  end loop;
  return code;
end $$;

-- Trigger: beim Insert Code setzen, falls leer
create or replace function public.set_invite_code_on_group_insert()
returns trigger language plpgsql as $$
begin
  if new.invite_code is null or new.invite_code = '' then
    new.invite_code := public.generate_group_invite_code();
  end if;
  return new;
end $$;

drop trigger if exists trg_group_invite_code on groups;
create trigger trg_group_invite_code
  before insert on groups
  for each row execute function public.set_invite_code_on_group_insert();

-- 3) Backfill für bestehende Gruppen ohne Code -----------------------------
do $$
declare
  r record;
begin
  for r in select id from groups where invite_code is null or invite_code = '' loop
    update groups set invite_code = public.generate_group_invite_code() where id = r.id;
  end loop;
end $$;

alter table groups alter column invite_code set not null;

-- 4) group_join_requests ---------------------------------------------------
create table if not exists group_join_requests (
  id           uuid        primary key default gen_random_uuid(),
  group_id     uuid        not null references groups(id)   on delete cascade,
  user_id      uuid        not null references profiles(id) on delete cascade,
  status       text        not null default 'pending'
               check (status in ('pending', 'accepted', 'rejected')),
  message      text,
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  unique (group_id, user_id)
);

create index if not exists group_join_requests_group_idx
  on group_join_requests (group_id, status);
create index if not exists group_join_requests_user_idx
  on group_join_requests (user_id, status);

alter table group_join_requests enable row level security;

-- RLS: User sieht eigene Requests
drop policy if exists "User sieht eigene Join-Requests" on group_join_requests;
create policy "User sieht eigene Join-Requests"
  on group_join_requests for select
  using (user_id = auth.uid());

-- RLS: Owner der Gruppe sieht alle Requests seiner Gruppe
drop policy if exists "Owner sieht Requests seiner Gruppe" on group_join_requests;
create policy "Owner sieht Requests seiner Gruppe"
  on group_join_requests for select
  using (
    exists (
      select 1 from group_members gm
      where gm.group_id = group_join_requests.group_id
        and gm.user_id  = auth.uid()
        and gm.role     = 'owner'
    )
  );

-- RLS: User darf eigenen Request anlegen
drop policy if exists "User erstellt eigenen Join-Request" on group_join_requests;
create policy "User erstellt eigenen Join-Request"
  on group_join_requests for insert
  with check (user_id = auth.uid());

-- RLS: User darf eigenen Request zurückziehen (löschen)
drop policy if exists "User zieht eigenen Join-Request zurück" on group_join_requests;
create policy "User zieht eigenen Join-Request zurück"
  on group_join_requests for delete
  using (user_id = auth.uid());

-- RLS: Owner darf Requests seiner Gruppe updaten (accept/reject)
drop policy if exists "Owner updated Requests seiner Gruppe" on group_join_requests;
create policy "Owner updated Requests seiner Gruppe"
  on group_join_requests for update
  using (
    exists (
      select 1 from group_members gm
      where gm.group_id = group_join_requests.group_id
        and gm.user_id  = auth.uid()
        and gm.role     = 'owner'
    )
  );

-- 5) RPC: accept_join_request (atomar: Request -> Member) -----------------
create or replace function public.accept_group_join_request(req_id uuid)
returns void language plpgsql security definer as $$
declare
  rec group_join_requests%rowtype;
  is_owner boolean;
begin
  select * into rec from group_join_requests where id = req_id for update;
  if not found then raise exception 'request not found'; end if;
  if rec.status <> 'pending' then raise exception 'request is not pending'; end if;

  select exists (
    select 1 from group_members gm
    where gm.group_id = rec.group_id
      and gm.user_id  = auth.uid()
      and gm.role     = 'owner'
  ) into is_owner;
  if not is_owner then raise exception 'only owner may accept requests'; end if;

  insert into group_members (group_id, user_id, role)
  values (rec.group_id, rec.user_id, 'passenger')
  on conflict (group_id, user_id) do nothing;

  update group_join_requests
     set status = 'accepted', responded_at = now()
   where id = req_id;
end $$;

create or replace function public.reject_group_join_request(req_id uuid)
returns void language plpgsql security definer as $$
declare
  is_owner boolean;
begin
  select exists (
    select 1 from group_members gm
    join   group_join_requests r on r.group_id = gm.group_id
    where  r.id = req_id
      and  gm.user_id = auth.uid()
      and  gm.role    = 'owner'
  ) into is_owner;
  if not is_owner then raise exception 'only owner may reject requests'; end if;

  update group_join_requests
     set status = 'rejected', responded_at = now()
   where id = req_id
     and status = 'pending';
end $$;

-- Schema-Cache neu laden für PostgREST
notify pgrst, 'reload schema';
