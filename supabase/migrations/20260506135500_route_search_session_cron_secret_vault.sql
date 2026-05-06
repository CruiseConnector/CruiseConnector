-- Remote operational note:
-- route_search_session_cron_secret was created in Supabase Vault during the
-- worker activation run from a generated value that is also configured as the
-- Edge Function secret ROUTE_SEARCH_SESSION_CRON_SECRET.
--
-- The actual secret value must never be committed to git. For fresh
-- environments, set the Edge secret and create the matching Vault secret before
-- enabling process_route_search_sessions_every_minute.
SELECT 1;
