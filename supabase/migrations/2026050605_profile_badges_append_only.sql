-- Keep profile badges as permanent achievements.
-- The app still recalculates current stats from routes/posts/groups, but badges
-- are merged with the existing profile value instead of being replaced by the
-- currently qualifying rules.

create or replace function public.normalize_badge_ids(p_badges jsonb)
returns jsonb
language sql
immutable
as $$
  with valid_badges(id, sort_order) as (
    values
      ('badge_01', 1),
      ('badge_02', 2),
      ('badge_03', 3),
      ('badge_04', 4),
      ('badge_05', 5),
      ('badge_06', 6),
      ('badge_07', 7),
      ('badge_08', 8),
      ('badge_09', 9),
      ('badge_10', 10),
      ('badge_13', 13),
      ('badge_14', 14)
  ),
  raw_badges(id) as (
    select
      case value
        when 'route_1' then 'badge_02'
        else value
      end
    from jsonb_array_elements_text(
      case
        when jsonb_typeof(coalesce(p_badges, '[]'::jsonb)) = 'array'
          then coalesce(p_badges, '[]'::jsonb)
        else '[]'::jsonb
      end
    )
  ),
  distinct_badges as (
    select distinct valid_badges.id, valid_badges.sort_order
    from raw_badges
    join valid_badges on valid_badges.id = raw_badges.id
  )
  select coalesce(jsonb_agg(id order by sort_order), '[]'::jsonb)
  from distinct_badges;
$$;

create or replace function public.merge_profile_badges(
  p_existing jsonb,
  p_incoming jsonb
)
returns jsonb
language sql
immutable
as $$
  select public.normalize_badge_ids(
    public.normalize_badge_ids(p_existing)
    || public.normalize_badge_ids(p_incoming)
  );
$$;

update public.profiles
set badges = public.normalize_badge_ids(badges)
where badges is not null;

create or replace function public.preserve_profile_badges()
returns trigger
language plpgsql
as $$
declare
  existing_badges jsonb := '[]'::jsonb;
begin
  if tg_op = 'UPDATE' then
    existing_badges := old.badges;
  end if;

  new.badges := public.merge_profile_badges(existing_badges, new.badges);
  return new;
end;
$$;

drop trigger if exists trg_preserve_profile_badges on public.profiles;
create trigger trg_preserve_profile_badges
  before insert or update of badges on public.profiles
  for each row execute function public.preserve_profile_badges();
