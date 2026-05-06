-- Saved route copies are append-only user library entries. A user should only
-- have one saved copy for the same source route; removing it from any screen
-- makes it disappear from profile, menu and analytics.

alter table public.routes
  add column if not exists source_route_id uuid
    references public.routes(id) on delete set null;

with ranked as (
  select
    id,
    row_number() over (
      partition by user_id, source_route_id
      order by created_at asc, id asc
    ) as rn
  from public.routes
  where source_route_id is not null
)
delete from public.routes r
using ranked
where r.id = ranked.id
  and ranked.rn > 1;

create unique index if not exists routes_user_source_route_unique_idx
  on public.routes (user_id, source_route_id)
  where source_route_id is not null;
