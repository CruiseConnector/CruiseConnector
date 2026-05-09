-- Harden route-pool curation tables/RPCs after applying the remote migration set.
-- Trusted Edge Functions use the service role, and pg_cron runs as the owning
-- database role, so public client access is not required for these internals.

alter table public.route_pool_curation_config enable row level security;
alter table public.route_pool_curation_runs enable row level security;

revoke all on table public.route_pool_curation_config from anon, authenticated;
revoke all on table public.route_pool_curation_runs from anon, authenticated;

revoke all on function public.invoke_route_pool_curation_edge() from public, anon, authenticated;
grant execute on function public.invoke_route_pool_curation_edge() to service_role;

revoke all on function public.queue_weekly_route_pool_curation(timestamptz) from public, anon, authenticated;
grant execute on function public.queue_weekly_route_pool_curation(timestamptz) to service_role;

alter function public.set_content_report_updated_at() set search_path = public;
alter function public.normalize_badge_ids(jsonb) set search_path = public;
alter function public.merge_profile_badges(jsonb, jsonb) set search_path = public;
alter function public.preserve_profile_badges() set search_path = public;
