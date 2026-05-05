-- Track whether a driven route was actually finished at the route end.
-- Partial rides can still earn stepped XP at 20/40/60/80%, but route-completion
-- badges only count rows where this flag is true.

alter table public.routes
  add column if not exists completed_at_end boolean not null default false;

create index if not exists idx_routes_user_completed_at_end
  on public.routes (user_id, created_at desc)
  where completed_at_end = true;
