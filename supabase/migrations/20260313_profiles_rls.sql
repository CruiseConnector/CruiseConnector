-- ─────────────────────────────────────────────────────────────────────────────
-- CruiseConnect — Profiles + Routes RLS
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. User-Profile Tabelle ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       TEXT,
  username    TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "User sieht eigenes Profil"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "User erstellt eigenes Profil"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "User aktualisiert eigenes Profil"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);


-- 2. Routes Tabelle erweitern ─────────────────────────────────────────────────
ALTER TABLE public.routes
  ADD COLUMN IF NOT EXISTS route_type      TEXT    DEFAULT 'ROUND_TRIP',
  ADD COLUMN IF NOT EXISTS duration_seconds FLOAT;


-- 3. RLS für Routes ───────────────────────────────────────────────────────────
ALTER TABLE public.routes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "User sieht eigene Routen"
  ON public.routes FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "User speichert eigene Routen"
  ON public.routes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "User löscht eigene Routen"
  ON public.routes FOR DELETE
  USING (auth.uid() = user_id);


-- 4. Trigger: Profil automatisch beim Signup anlegen ─────────────────────────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, username)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'username', split_part(NEW.email, '@', 1))
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
