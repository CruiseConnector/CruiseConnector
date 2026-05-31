-- Push-Notifications: Device-Token-Registry + Fanout-Webhook.
-- 2026-05-31 (vucko): Echte Handy-Push für ALLE Notification-Typen.
--
-- Architektur (bleibt maximal in Supabase, FCM ist nur das Auslieferungsrohr):
--   1. Client registriert sein FCM-Device-Token via RPC register_device_token().
--   2. Jeder INSERT in public.notifications (likes, kommentare, reposts,
--      follows, weather_recommendation, …) triggert per pg_net einen POST an
--      die Edge-Function send-push.
--   3. send-push holt alle Tokens des user_id und stellt via FCM HTTP v1 zu.
--
-- Secrets liegen im Vault / in den Function-Env — NIEMALS in dieser Migration.
-- Wiederverwendete Vault-Secrets:
--   * route_pool_healing_project_url  (existiert bereits, = https://<ref>.supabase.co)
-- Neues Vault-Secret (vom User zu setzen, sonst ist der Push-Fanout inaktiv):
--   * push_webhook_secret             (= identisch zu Function-Env PUSH_WEBHOOK_SECRET)

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS supabase_vault CASCADE;

-- ── Device-Token-Registry ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_device_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token text NOT NULL,
  platform text NOT NULL DEFAULT 'unknown'
    CHECK (platform IN ('android', 'ios', 'web', 'macos', 'unknown')),
  device_label text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_device_tokens_token_key UNIQUE (token)
);

CREATE INDEX IF NOT EXISTS idx_user_device_tokens_user
  ON public.user_device_tokens(user_id);

ALTER TABLE public.user_device_tokens ENABLE ROW LEVEL SECURITY;

-- User verwaltet nur seine eigenen Tokens. Der Fanout (Edge-Function) liest
-- mit service_role und umgeht RLS.
DROP POLICY IF EXISTS "device_tokens_select_own" ON public.user_device_tokens;
CREATE POLICY "device_tokens_select_own" ON public.user_device_tokens
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "device_tokens_insert_own" ON public.user_device_tokens;
CREATE POLICY "device_tokens_insert_own" ON public.user_device_tokens
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "device_tokens_update_own" ON public.user_device_tokens;
CREATE POLICY "device_tokens_update_own" ON public.user_device_tokens
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "device_tokens_delete_own" ON public.user_device_tokens;
CREATE POLICY "device_tokens_delete_own" ON public.user_device_tokens
  FOR DELETE USING (auth.uid() = user_id);

-- Idempotenter Upsert vom Client (RPC) — user_id wird serverseitig aus auth
-- gesetzt, der Client kann also keine fremden Tokens registrieren.
CREATE OR REPLACE FUNCTION public.register_device_token(
  p_token text,
  p_platform text DEFAULT 'unknown',
  p_device_label text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR p_token IS NULL OR length(trim(p_token)) = 0 THEN
    RETURN;
  END IF;
  INSERT INTO public.user_device_tokens (user_id, token, platform, device_label)
  VALUES (v_uid, p_token, COALESCE(NULLIF(trim(p_platform), ''), 'unknown'), p_device_label)
  ON CONFLICT (token) DO UPDATE SET
    user_id      = EXCLUDED.user_id,
    platform     = EXCLUDED.platform,
    device_label = COALESCE(EXCLUDED.device_label, public.user_device_tokens.device_label),
    updated_at   = now(),
    last_seen_at = now();
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_device_token(text, text, text) TO authenticated;

-- ── Fanout-Webhook bei neuer Notification ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_push_on_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_base_url text;
  v_secret text;
BEGIN
  -- Basis-URL aus dem bestehenden Worker-Vault-Secret + dediziertes
  -- Push-Webhook-Secret. Beides optional: fehlt eines, ist der Push-Fanout
  -- schlicht inaktiv (kein Fehler — die In-App-Notification bleibt unberührt).
  SELECT decrypted_secret INTO v_base_url
  FROM vault.decrypted_secrets
  WHERE name = 'route_pool_healing_project_url' LIMIT 1;

  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets
  WHERE name = 'push_webhook_secret' LIMIT 1;

  IF v_base_url IS NULL OR v_secret IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := v_base_url || '/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secret
    ),
    body := jsonb_build_object('record', row_to_json(NEW)),
    timeout_milliseconds := 8000
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Ein Push-Fehler darf die Notification-Erstellung NIE blockieren.
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_push_on_notification ON public.notifications;
CREATE TRIGGER trg_notify_push_on_notification
AFTER INSERT ON public.notifications
FOR EACH ROW EXECUTE FUNCTION public.notify_push_on_notification();
