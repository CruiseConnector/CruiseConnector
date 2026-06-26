-- 2026-06-25 (vucko): group_messages.user_id hatte nur einen FK auf auth.users,
-- aber das App-Select nutzt den PostgREST-Embed `profiles:user_id(...)` (wie
-- community_messages). Ohne FK group_messages→profiles kann PostgREST die
-- Beziehung nicht auflösen → fetchMessages UND sendMessage(.select()) werfen
-- PGRST200 → Chat tot (Nachricht „nicht gesendet", niemand sieht etwas).
-- Fix: zusätzlichen FK auf profiles(id) — exakt wie community_messages.
do $$ begin
  alter table public.group_messages
    add constraint group_messages_user_id_profiles_fkey
    foreign key (user_id) references public.profiles(id) on delete cascade;
exception when duplicate_object then null; end $$;
