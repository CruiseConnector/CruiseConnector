-- Autonomous route-pool healing controls.
-- Adds budget and execution metadata without changing the existing unique
-- coverage/job keys. The worker remains bounded by these columns and never
-- creates ad-hoc micro clusters.

ALTER TABLE public.route_seed_jobs
  DROP CONSTRAINT IF EXISTS route_seed_jobs_status_check;

ALTER TABLE public.route_seed_jobs
  ADD CONSTRAINT route_seed_jobs_status_check CHECK (
    status IN (
      'queued',
      'running',
      'completed',
      'failed',
      'cooldown',
      'cancelled',
      'paused_budget'
    )
  );

ALTER TABLE public.route_seed_jobs
  ADD COLUMN IF NOT EXISTS job_kind text NOT NULL DEFAULT 'seed_healing'
    CHECK (job_kind IN ('seed_healing', 'manual_seed', 'coverage_report')),
  ADD COLUMN IF NOT EXISTS max_mapbox_calls integer NOT NULL DEFAULT 8
    CHECK (max_mapbox_calls BETWEEN 0 AND 50),
  ADD COLUMN IF NOT EXISTS mapbox_calls_used integer NOT NULL DEFAULT 0
    CHECK (mapbox_calls_used >= 0),
  ADD COLUMN IF NOT EXISTS verified_inserted_count integer NOT NULL DEFAULT 0
    CHECK (verified_inserted_count >= 0),
  ADD COLUMN IF NOT EXISTS candidate_inserted_count integer NOT NULL DEFAULT 0
    CHECK (candidate_inserted_count >= 0),
  ADD COLUMN IF NOT EXISTS daily_attempt_budget integer NOT NULL DEFAULT 12
    CHECK (daily_attempt_budget BETWEEN 0 AND 200),
  ADD COLUMN IF NOT EXISTS monthly_attempt_budget integer NOT NULL DEFAULT 120
    CHECK (monthly_attempt_budget BETWEEN 0 AND 2000),
  ADD COLUMN IF NOT EXISTS daily_attempt_count integer NOT NULL DEFAULT 0
    CHECK (daily_attempt_count >= 0),
  ADD COLUMN IF NOT EXISTS monthly_attempt_count integer NOT NULL DEFAULT 0
    CHECK (monthly_attempt_count >= 0),
  ADD COLUMN IF NOT EXISTS budget_window_date date NOT NULL DEFAULT current_date,
  ADD COLUMN IF NOT EXISTS budget_window_month date NOT NULL DEFAULT date_trunc('month', now())::date,
  ADD COLUMN IF NOT EXISTS next_retry_at timestamptz,
  ADD COLUMN IF NOT EXISTS completed_reason text;

CREATE INDEX IF NOT EXISTS idx_route_seed_jobs_healing_queue
  ON public.route_seed_jobs (
    status,
    next_retry_at,
    cooldown_until,
    priority DESC,
    updated_at ASC
  )
  WHERE status IN ('queued', 'cooldown');

CREATE INDEX IF NOT EXISTS idx_route_seed_jobs_budget_windows
  ON public.route_seed_jobs (
    budget_window_date,
    budget_window_month,
    status
  );

ALTER TABLE public.route_pool_coverage
  ADD COLUMN IF NOT EXISTS healing_status text NOT NULL DEFAULT 'idle'
    CHECK (
      healing_status IN (
        'idle',
        'healing_queued',
        'healing_running',
        'healing_failed_cooldown',
        'healing_paused_budget',
        'hard_region_curated_needed'
      )
    ),
  ADD COLUMN IF NOT EXISTS healing_priority integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS healing_attempt_count integer NOT NULL DEFAULT 0
    CHECK (healing_attempt_count >= 0),
  ADD COLUMN IF NOT EXISTS healing_failure_count integer NOT NULL DEFAULT 0
    CHECK (healing_failure_count >= 0),
  ADD COLUMN IF NOT EXISTS daily_attempt_budget integer NOT NULL DEFAULT 12
    CHECK (daily_attempt_budget BETWEEN 0 AND 200),
  ADD COLUMN IF NOT EXISTS monthly_attempt_budget integer NOT NULL DEFAULT 120
    CHECK (monthly_attempt_budget BETWEEN 0 AND 2000),
  ADD COLUMN IF NOT EXISTS healing_calls_today integer NOT NULL DEFAULT 0
    CHECK (healing_calls_today >= 0),
  ADD COLUMN IF NOT EXISTS healing_calls_month integer NOT NULL DEFAULT 0
    CHECK (healing_calls_month >= 0),
  ADD COLUMN IF NOT EXISTS healing_budget_window_date date NOT NULL DEFAULT current_date,
  ADD COLUMN IF NOT EXISTS healing_budget_window_month date NOT NULL DEFAULT date_trunc('month', now())::date,
  ADD COLUMN IF NOT EXISTS next_healing_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_healing_job_id uuid REFERENCES public.route_seed_jobs(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_route_pool_coverage_healing_status
  ON public.route_pool_coverage (
    healing_status,
    next_healing_at,
    healing_priority DESC,
    updated_at DESC
  );
