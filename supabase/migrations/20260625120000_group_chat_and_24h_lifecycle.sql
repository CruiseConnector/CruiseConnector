-- ============================================================
-- Gruppen-Chat + „Fahrt-Ende schließt Gruppe" + 24h-Auto-Löschung
-- 2026-06-25 (vucko)
-- Idempotent: kann gefahrlos erneut angewendet werden.
-- ============================================================

-- 1) Gruppe „abgeschlossen": Zeitpunkt, ab dem die 24h-Frist läuft.
alter table public.groups add column if not exists closed_at timestamptz;

-- 2) Chat-Tabelle (gespiegelt von community_messages). ON DELETE CASCADE →
--    wird mit der Gruppe automatisch mitgelöscht.
create table if not exists public.group_messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint group_messages_body_len check (length(btrim(body)) between 1 and 2000)
);
create index if not exists group_messages_group_created_idx
  on public.group_messages (group_id, created_at);

alter table public.group_messages enable row level security;

-- Helper (SECURITY DEFINER → umgeht RLS auf group_members, keine Rekursion).
create or replace function public.is_group_member(p_group_id uuid, p_user_id uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.group_members gm
    where gm.group_id = p_group_id and gm.user_id = p_user_id
  );
$$;

-- RLS: lesen + schreiben nur Mitglieder; löschen nur eigene Nachricht.
-- Schreiben bleibt auch nach „closed" erlaubt (man soll noch was klären können).
drop policy if exists group_messages_select on public.group_messages;
create policy group_messages_select on public.group_messages
  for select using (public.is_group_member(group_id, auth.uid()));

drop policy if exists group_messages_insert on public.group_messages;
create policy group_messages_insert on public.group_messages
  for insert with check (
    user_id = auth.uid() and public.is_group_member(group_id, auth.uid())
  );

drop policy if exists group_messages_delete on public.group_messages;
create policy group_messages_delete on public.group_messages
  for delete using (user_id = auth.uid());

-- 3) Realtime einschalten (Chat live).
do $$ begin
  alter publication supabase_realtime add table public.group_messages;
exception when duplicate_object then null; end $$;

-- 4) „Fahrt abgeschlossen → Gruppe abgeschlossen" — von der App aufrufbar.
create or replace function public.close_group(p_group_id uuid)
returns void language sql security definer set search_path = public as $$
  update public.groups
     set closed_at = coalesce(closed_at, now()), is_active = false
   where id = p_group_id
     and (created_by = auth.uid() or public.is_group_member(p_group_id, auth.uid()));
$$;

-- 5) Cron: stündlich (a) hängengebliebene aktive Gruppen nach 12h auto-schließen
--    (Sicherheitsnetz), (b) geschlossene Gruppen 24h nach Abschluss löschen.
--    Löschen kaskadiert auf group_messages + group_members + group_join_requests;
--    trips/routes/drive_sessions behalten ihre Historie (group_id → NULL).
select cron.schedule(
  'auto-close-stale-groups',
  '13 * * * *',
  $cron$ update public.groups set closed_at = now(), is_active = false
         where closed_at is null and is_active = true
           and coalesce(activated_at, created_at) < now() - interval '12 hours' $cron$
);

select cron.schedule(
  'delete-closed-groups-24h',
  '17 * * * *',
  $cron$ delete from public.groups
         where closed_at is not null and closed_at < now() - interval '24 hours' $cron$
);
