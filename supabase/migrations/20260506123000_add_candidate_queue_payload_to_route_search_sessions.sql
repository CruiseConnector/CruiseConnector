-- Store compact pre-hydration candidate queues for long interactive
-- roundtrip searches. Workers hydrate these exact plans instead of
-- reconstructing different candidates.

ALTER TABLE public.route_search_sessions
  ADD COLUMN IF NOT EXISTS candidate_queue_payload jsonb NOT NULL DEFAULT '[]'::jsonb;
