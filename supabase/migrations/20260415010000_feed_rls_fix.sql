-- =============================================================================
-- RLS-Härtung für Feed + Gruppen.
-- 1. posts: öffentliche Posts sind für alle lesbar; private Posts
--    (visibility='followers') nur für Follower (status='accepted') und den
--    Autor selbst.
-- 2. groups / group_members: Creator MUSS als group_member mit Rolle 'owner'
--    existieren — dafür sorgt der Trigger. Wir sichern zusätzlich ab, dass
--    die bestehenden Policies Creator-Zugriff nicht blockieren.
-- =============================================================================

-- 1) posts -----------------------------------------------------------------
drop policy if exists "Posts sind öffentlich lesbar"    on posts;
drop policy if exists "Posts lesbar nach Visibility"    on posts;

create policy "Posts lesbar nach Visibility"
  on posts for select
  using (
    visibility = 'public'
    or user_id = auth.uid()
    or (
      visibility = 'followers'
      and exists (
        select 1 from follows f
        where f.follower_id  = auth.uid()
          and f.following_id = posts.user_id
          and f.status       = 'accepted'
      )
    )
  );

-- 2) groups / group_members ------------------------------------------------
-- Creator als Owner sicherstellen (idempotent — falls Trigger mal nicht lief).
insert into group_members (group_id, user_id, role)
select g.id, g.created_by, 'owner'
from   groups g
where  not exists (
  select 1 from group_members gm
  where  gm.group_id = g.id
    and  gm.user_id  = g.created_by
)
on conflict (group_id, user_id) do update set role = 'owner';

-- Backup-Policy: Creator darf seine Gruppe immer sehen, auch wenn sie
-- irgendwann mal nicht öffentlich lesbar wäre.
drop policy if exists "Creator kann eigene Gruppe lesen" on groups;
create policy "Creator kann eigene Gruppe lesen"
  on groups for select
  using (created_by = auth.uid());
