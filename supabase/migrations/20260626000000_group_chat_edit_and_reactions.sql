-- 2026-06-26 (vucko): Gruppen-Chat — Nachrichten bearbeiten + Emoji-Reaktionen.
-- NUR Gruppen-Chats (group_messages), NICHT Community/Posts.
--
-- 1) edited_at-Spalte + UPDATE-RLS (eigene Nachricht editieren/soft-deleten).
-- 2) group_message_reactions (eine Reaktion je User+Emoji+Nachricht).
-- 3) is_group_message_member()-Helper (SECURITY DEFINER) für die Reaktions-RLS.
-- 4) Realtime-Publication für Live-Reaktionen.

-- 1) Bearbeiten -------------------------------------------------------------
alter table public.group_messages
  add column if not exists edited_at timestamptz;

drop policy if exists group_messages_update on public.group_messages;
create policy group_messages_update on public.group_messages
  for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- 2) Reaktionen -------------------------------------------------------------
create table if not exists public.group_message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.group_messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  unique (message_id, user_id, emoji)
);

create index if not exists group_message_reactions_message_idx
  on public.group_message_reactions(message_id);

alter table public.group_message_reactions enable row level security;

-- 3) Mitgliedschafts-Helper (umgeht RLS-Rekursion) --------------------------
create or replace function public.is_group_message_member(
  p_message_id uuid,
  p_user_id uuid
) returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
as $$
  select exists (
    select 1 from public.group_messages gm
    join public.group_members m on m.group_id = gm.group_id
    where gm.id = p_message_id and m.user_id = p_user_id
  );
$$;

-- Reaktionen lesen: jedes Gruppen-Mitglied. Setzen: nur eigene + Mitglied.
-- Entfernen: nur eigene.
drop policy if exists gmr_select on public.group_message_reactions;
create policy gmr_select on public.group_message_reactions
  for select
  using (is_group_message_member(message_id, auth.uid()));

drop policy if exists gmr_insert on public.group_message_reactions;
create policy gmr_insert on public.group_message_reactions
  for insert
  with check (
    user_id = auth.uid()
    and is_group_message_member(message_id, auth.uid())
  );

drop policy if exists gmr_delete on public.group_message_reactions;
create policy gmr_delete on public.group_message_reactions
  for delete
  using (user_id = auth.uid());

-- 4) Live-Reaktionen --------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'group_message_reactions'
  ) then
    alter publication supabase_realtime add table public.group_message_reactions;
  end if;
end $$;
