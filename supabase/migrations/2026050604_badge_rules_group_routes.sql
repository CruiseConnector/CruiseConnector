-- Badge rule support:
-- - route rows can remember the group session that produced them
-- - old badge ids are removed from profiles so the app can repopulate only the
--   active Badge_01/02/03/04/05/06/07/08/09/10/13/14 set on the next sync.

alter table public.routes
  add column if not exists group_id uuid
    references public.groups(id) on delete set null;

create index if not exists idx_routes_user_group_completed
  on public.routes (user_id, group_id, created_at desc)
  where group_id is not null and completed_at_end = true;

update public.profiles
set badges = coalesce((
  select jsonb_agg(distinct mapped.badge)
  from (
    select case badge
      when 'route_1' then 'badge_02'
      else badge
    end as badge
    from jsonb_array_elements_text(coalesce(public.profiles.badges, '[]'::jsonb)) as existing(badge)
  ) as mapped
  where mapped.badge in (
    'badge_01',
    'badge_02',
    'badge_03',
    'badge_04',
    'badge_05',
    'badge_06',
    'badge_07',
    'badge_08',
    'badge_09',
    'badge_10',
    'badge_13',
    'badge_14'
  )
), '[]'::jsonb)
where badges is not null;
