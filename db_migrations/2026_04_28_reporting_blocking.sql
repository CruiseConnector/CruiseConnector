-- ============================================================================
-- CruiseConnect — Melde- & Blockier-Funktion (UGC-Compliance Apple/Google)
-- ============================================================================
-- Diese Migration legt die Tabellen `user_blocks` und `content_reports` an,
-- ergänzt `profiles.is_banned`, baut RLS-Policies, RPCs und einen Trigger,
-- der die Posts gebannter User auf `is_hidden=true` setzt.
--
-- Auf Supabase Studio in den SQL-Editor einfügen oder via `supabase db push`
-- deployen. Alle Statements sind idempotent — kann gefahrlos mehrfach
-- ausgeführt werden.
-- ============================================================================

-- ─── 1. Schema-Erweiterungen ────────────────────────────────────────────────

alter table public.profiles
  add column if not exists is_banned boolean default false,
  add column if not exists banned_at timestamptz,
  add column if not exists banned_reason text;

alter table public.posts
  add column if not exists is_hidden boolean default false;


-- ─── 2. user_blocks ─────────────────────────────────────────────────────────

create table if not exists public.user_blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  -- Selbst blockieren ergibt keinen Sinn.
  constraint user_blocks_no_self check (blocker_id <> blocked_id)
);

create index if not exists idx_user_blocks_blocker on public.user_blocks(blocker_id);
create index if not exists idx_user_blocks_blocked on public.user_blocks(blocked_id);

alter table public.user_blocks enable row level security;

-- Eigene Blocks lesen.
do $$ begin
  if not exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='user_blocks'
       and policyname='user_blocks_owner_select'
  ) then
    create policy "user_blocks_owner_select"
      on public.user_blocks for select
      using (auth.uid() = blocker_id);
  end if;
end $$;

-- Nur eigene Blocks anlegen.
do $$ begin
  if not exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='user_blocks'
       and policyname='user_blocks_owner_insert'
  ) then
    create policy "user_blocks_owner_insert"
      on public.user_blocks for insert
      with check (auth.uid() = blocker_id);
  end if;
end $$;

-- Eigene Blocks löschen (= unblock).
do $$ begin
  if not exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='user_blocks'
       and policyname='user_blocks_owner_delete'
  ) then
    create policy "user_blocks_owner_delete"
      on public.user_blocks for delete
      using (auth.uid() = blocker_id);
  end if;
end $$;


-- ─── 3. content_reports ─────────────────────────────────────────────────────

create table if not exists public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_user_id uuid references public.profiles(id) on delete cascade,
  post_id uuid references public.posts(id) on delete cascade,
  comment_id uuid references public.comments(id) on delete cascade,
  reason text not null check (
    reason in (
      'spam',
      'harassment',
      'hate_speech',
      'sexual_content',
      'violence',
      'self_harm',
      'illegal',
      'other'
    )
  ),
  details text,                         -- optional: Freitext-Erklärung
  status text not null default 'open'   -- open | reviewing | actioned | dismissed
    check (status in ('open','reviewing','actioned','dismissed')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id),
  resolution_notes text,
  -- Mind. eines der drei Targets muss gesetzt sein.
  constraint content_reports_target_required check (
    reported_user_id is not null or post_id is not null or comment_id is not null
  )
);

create index if not exists idx_reports_status_created
  on public.content_reports(status, created_at desc);
create index if not exists idx_reports_reporter
  on public.content_reports(reporter_id);
create index if not exists idx_reports_post
  on public.content_reports(post_id) where post_id is not null;
create index if not exists idx_reports_user
  on public.content_reports(reported_user_id) where reported_user_id is not null;

alter table public.content_reports enable row level security;

-- User darf seine eigenen Reports lesen.
do $$ begin
  if not exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='content_reports'
       and policyname='reports_reporter_select'
  ) then
    create policy "reports_reporter_select"
      on public.content_reports for select
      using (auth.uid() = reporter_id);
  end if;
end $$;

-- User darf nur Reports im eigenen Namen anlegen, status muss 'open' sein.
do $$ begin
  if not exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='content_reports'
       and policyname='reports_reporter_insert'
  ) then
    create policy "reports_reporter_insert"
      on public.content_reports for insert
      with check (
        auth.uid() = reporter_id
        and status = 'open'
        and resolved_at is null
      );
  end if;
end $$;

-- Update/Delete: nur durch Service-Role (Admin-RPCs). Keine User-Policy.


-- ─── 4. Block-Helper für RLS auf posts/comments ────────────────────────────
-- Inline in Queries via `not exists (select 1 from user_blocks ...)` ist
-- ineffizient. Ein SECURITY DEFINER Helper ist sauberer.

create or replace function public.is_blocked_either_way(other uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_blocks
     where (blocker_id = auth.uid() and blocked_id = other)
        or (blocker_id = other and blocked_id = auth.uid())
  );
$$;
grant execute on function public.is_blocked_either_way(uuid) to authenticated;


-- ─── 5. RPCs für Reporting & Blocking ──────────────────────────────────────

-- Block einen User. Idempotent: doppeltes Insert wird durch PK abgefangen.
create or replace function public.block_user(target uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if uid = target then raise exception 'cannot block yourself'; end if;
  insert into public.user_blocks(blocker_id, blocked_id)
  values (uid, target)
  on conflict do nothing;

  -- Bestehende Follow-Beziehungen in beide Richtungen entfernen — Blocken
  -- impliziert Entfolgen.
  delete from public.follows
   where (follower_id = uid and following_id = target)
      or (follower_id = target and following_id = uid);
end $$;
grant execute on function public.block_user(uuid) to authenticated;

create or replace function public.unblock_user(target uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not authenticated'; end if;
  delete from public.user_blocks
   where blocker_id = uid and blocked_id = target;
end $$;
grant execute on function public.unblock_user(uuid) to authenticated;

create or replace function public.submit_content_report(
  p_reason text,
  p_reported_user_id uuid default null,
  p_post_id uuid default null,
  p_comment_id uuid default null,
  p_details text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  new_id uuid;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_reported_user_id is null
     and p_post_id is null
     and p_comment_id is null then
    raise exception 'at least one target required';
  end if;
  insert into public.content_reports(
    reporter_id, reported_user_id, post_id, comment_id, reason, details
  ) values (
    uid, p_reported_user_id, p_post_id, p_comment_id, p_reason, p_details
  )
  returning id into new_id;
  return new_id;
end $$;
grant execute on function public.submit_content_report(text, uuid, uuid, uuid, text)
  to authenticated;


-- ─── 6. Admin-RPCs (für Devs / Service-Role) ───────────────────────────────
-- Diese sollten NUR mit Service-Role aufgerufen werden. Die Policies hier
-- erlauben jeden authenticated; Schutz erfolgt über `is_admin()`-Check.

-- Wer darf Admin-Aktionen? Aktuell: User mit Eintrag in `app_admins`.
create table if not exists public.app_admins (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.app_admins enable row level security;
-- Admins können sich selbst sehen (für UI-Checks).
do $$ begin
  if not exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='app_admins'
       and policyname='admins_self_select'
  ) then
    create policy "admins_self_select"
      on public.app_admins for select
      using (auth.uid() = user_id);
  end if;
end $$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.app_admins where user_id = auth.uid()
  );
$$;
grant execute on function public.is_admin() to authenticated;

-- Post löschen (Admin).
create or replace function public.admin_delete_post(p_post_id uuid, p_notes text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid := auth.uid();
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  delete from public.posts where id = p_post_id;
  -- Reports zu diesem Post als 'actioned' markieren.
  update public.content_reports
     set status = 'actioned',
         resolved_at = now(),
         resolved_by = uid,
         resolution_notes = coalesce(p_notes, 'post deleted')
   where post_id = p_post_id and status in ('open','reviewing');
end $$;
grant execute on function public.admin_delete_post(uuid, text) to authenticated;

-- User bannen (soft-delete: Posts versteckt, Profil markiert).
create or replace function public.admin_ban_user(p_user_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid := auth.uid();
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  update public.profiles
     set is_banned = true,
         banned_at = now(),
         banned_reason = p_reason
   where id = p_user_id;
  -- Trigger setzt `is_hidden=true` auf allen seinen Posts (siehe unten).
  update public.content_reports
     set status = 'actioned',
         resolved_at = now(),
         resolved_by = uid,
         resolution_notes = coalesce(p_reason, 'user banned')
   where reported_user_id = p_user_id and status in ('open','reviewing');
end $$;
grant execute on function public.admin_ban_user(uuid, text) to authenticated;

create or replace function public.admin_unban_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  update public.profiles
     set is_banned = false,
         banned_at = null,
         banned_reason = null
   where id = p_user_id;
  update public.posts
     set is_hidden = false
   where user_id = p_user_id;
end $$;
grant execute on function public.admin_unban_user(uuid) to authenticated;

create or replace function public.admin_resolve_report(
  p_report_id uuid,
  p_status text,
  p_notes text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid := auth.uid();
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if p_status not in ('actioned','dismissed','reviewing') then
    raise exception 'invalid status';
  end if;
  update public.content_reports
     set status = p_status,
         resolved_at = case when p_status = 'reviewing' then null else now() end,
         resolved_by = case when p_status = 'reviewing' then null else uid end,
         resolution_notes = p_notes
   where id = p_report_id;
end $$;
grant execute on function public.admin_resolve_report(uuid, text, text) to authenticated;


-- ─── 7. Trigger: Posts ausblenden, wenn User gebannt wird ──────────────────

create or replace function public.fn_hide_posts_on_ban()
returns trigger
language plpgsql
as $$
begin
  if new.is_banned = true and (old.is_banned is distinct from true) then
    update public.posts
       set is_hidden = true
     where user_id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists trg_hide_posts_on_ban on public.profiles;
create trigger trg_hide_posts_on_ban
  after update of is_banned on public.profiles
  for each row execute function public.fn_hide_posts_on_ban();


-- ─── 8. Admin-View für Devs (Reports-Inbox) ────────────────────────────────
-- Konsolidierte Sicht: jeder Report mit Reporter + Target (User/Post)
-- für schnelles Triage. Lese-Zugriff nur für Admins.

create or replace view public.v_admin_reports_inbox as
  select
    r.id, r.reason, r.details, r.status, r.created_at, r.resolved_at,
    r.reporter_id,
    rep.username  as reporter_username,
    rep.email     as reporter_email,
    r.reported_user_id,
    rep_u.username as reported_username,
    rep_u.email   as reported_email,
    rep_u.is_banned as reported_user_banned,
    r.post_id,
    p.content     as post_content,
    p.user_id     as post_author_id,
    pa.username   as post_author_username,
    p.is_hidden   as post_hidden,
    r.comment_id,
    c.content     as comment_content
  from public.content_reports r
  left join public.profiles rep   on rep.id = r.reporter_id
  left join public.profiles rep_u on rep_u.id = r.reported_user_id
  left join public.posts p        on p.id = r.post_id
  left join public.profiles pa    on pa.id = p.user_id
  left join public.comments c     on c.id = r.comment_id;

revoke all on public.v_admin_reports_inbox from public;
grant select on public.v_admin_reports_inbox to authenticated;

-- RLS auf die View — nur Admins sehen Inhalt.
alter view public.v_admin_reports_inbox set (security_invoker = on);
-- Da wir `security_invoker` setzen, fragen wir is_admin() in einer
-- zusätzlichen Policy auf dem Underlying-Table ab — aber content_reports
-- hat schon `reports_reporter_select`. Für Admins lassen wir eine Policy zu:
do $$ begin
  if not exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='content_reports'
       and policyname='reports_admin_select'
  ) then
    create policy "reports_admin_select"
      on public.content_reports for select
      using (public.is_admin());
  end if;
end $$;
