-- =============================================================================
-- PostgREST-Join-Fix: groups.created_by -> profiles.id
-- Ohne diesen FK kennt der Schema-Cache die Relation nicht und
-- der nested Select .select('*, profiles:created_by(...)') scheitert mit
-- PGRST200 ("Could not find a relationship between 'groups' and 'created_by'").
-- =============================================================================

-- 1) Defensive Backfill: Sicherstellen, dass jede groups.created_by einen
--    passenden profiles-Eintrag hat. Falls nicht, aus auth.users nachziehen.
insert into profiles (id, email, username)
select u.id, u.email, coalesce(u.raw_user_meta_data->>'username', split_part(u.email, '@', 1))
from   auth.users u
where  u.id in (select distinct created_by from groups where created_by is not null)
  and  u.id not in (select id from profiles)
on conflict (id) do nothing;

-- 2) FK anlegen (idempotent)
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where  constraint_name = 'groups_created_by_profiles_fkey'
      and  table_name      = 'groups'
  ) then
    alter table groups
      add constraint groups_created_by_profiles_fkey
      foreign key (created_by) references profiles(id)
      on delete set null;
  end if;
end $$;

-- 3) PostgREST Schema-Cache neu laden (ohne wird der FK nicht erkannt!)
notify pgrst, 'reload schema';
