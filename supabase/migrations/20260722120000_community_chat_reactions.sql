-- 2026-07-22 (vucko): Community-Chat — Emoji-Reaktionen (langer Druck auf eine
-- Nachricht), gespiegelt 1:1 von der bereits live laufenden Gruppen-Chat-
-- Lösung (20260626000000_group_chat_edit_and_reactions.sql). NUR
-- community_messages, NICHT group_messages.

create table if not exists public.community_message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.community_messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  unique (message_id, user_id, emoji)
);

create index if not exists community_message_reactions_message_idx
  on public.community_message_reactions(message_id);

alter table public.community_message_reactions enable row level security;

-- Mitgliedschafts-Helper (umgeht RLS-Rekursion), analog is_group_message_member.
create or replace function public.is_community_message_member(
  p_message_id uuid,
  p_user_id uuid
) returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
as $$
  select exists (
    select 1 from public.community_messages cm
    join public.community_members m on m.community_id = cm.community_id
    where cm.id = p_message_id and m.user_id = p_user_id
  );
$$;

-- Reaktionen lesen: jedes Community-Mitglied. Setzen: nur eigene + Mitglied.
-- Entfernen: nur eigene.
drop policy if exists cmr_select on public.community_message_reactions;
create policy cmr_select on public.community_message_reactions
  for select
  using (is_community_message_member(message_id, auth.uid()));

drop policy if exists cmr_insert on public.community_message_reactions;
create policy cmr_insert on public.community_message_reactions
  for insert
  with check (
    user_id = auth.uid()
    and is_community_message_member(message_id, auth.uid())
  );

drop policy if exists cmr_delete on public.community_message_reactions;
create policy cmr_delete on public.community_message_reactions
  for delete
  using (user_id = auth.uid());

-- Live-Reaktionen (Realtime-Publication).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'community_message_reactions'
  ) then
    alter publication supabase_realtime add table public.community_message_reactions;
  end if;
end $$;
