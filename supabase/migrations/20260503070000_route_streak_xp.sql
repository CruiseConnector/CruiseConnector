-- XP breakdown per driven route.
-- Keeps awarded XP stable even if the balancing formula changes later.

alter table public.routes
  add column if not exists xp_distance int,
  add column if not exists xp_curve_bonus int,
  add column if not exists xp_style_bonus int,
  add column if not exists xp_base int,
  add column if not exists xp_multiplier numeric(4, 2),
  add column if not exists xp_streak_days int,
  add column if not exists xp_awarded int;

create index if not exists idx_routes_user_xp_created
  on public.routes (user_id, created_at desc)
  where driven_km is not null and driven_km > 0;
