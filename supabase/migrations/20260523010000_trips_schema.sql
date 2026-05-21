-- Trip-Modus Schema (vucko Task #3)
--
-- Multi-Stop Touren mit Pause/Resume + Group-Sharing.
--
-- - trips: Master-Record (owner, group, status, lifecycle)
-- - trip_stops: Wegpunkte (overnight/lunch/photo/...)
-- - trip_segments: Live-generierte Routen zwischen aufeinanderfolgenden Stops

CREATE TABLE IF NOT EXISTS public.trips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  group_id uuid REFERENCES public.groups(id) ON DELETE SET NULL,
  title text NOT NULL,
  description text,

  -- Lifecycle
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'planned', 'active', 'paused', 'completed', 'cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  planned_start_at timestamptz,
  started_at timestamptz,
  paused_at timestamptz,
  resumed_at timestamptz,
  finished_at timestamptz,

  -- Aggregierte Stats (von trip_segments)
  total_distance_km double precision DEFAULT 0,
  total_duration_seconds integer DEFAULT 0,
  stop_count integer DEFAULT 0,

  -- Default-Settings für Segmente
  default_style text DEFAULT 'Sport Mode',
  default_avoid_highways boolean DEFAULT false,

  -- Sharing
  is_public boolean DEFAULT false,
  shareable_code text UNIQUE
);

CREATE INDEX IF NOT EXISTS idx_trips_owner ON public.trips(owner_id);
CREATE INDEX IF NOT EXISTS idx_trips_group ON public.trips(group_id) WHERE group_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_trips_status ON public.trips(status);

CREATE TABLE IF NOT EXISTS public.trip_stops (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id uuid NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  sequence integer NOT NULL,
  name text NOT NULL,
  lat double precision NOT NULL,
  lng double precision NOT NULL,
  stop_type text NOT NULL DEFAULT 'waypoint'
    CHECK (stop_type IN ('start', 'waypoint', 'overnight', 'lunch', 'photo', 'fuel', 'destination')),
  planned_arrival timestamptz,
  actual_arrival timestamptz,
  planned_duration_minutes integer DEFAULT 0,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (trip_id, sequence)
);

CREATE INDEX IF NOT EXISTS idx_trip_stops_trip ON public.trip_stops(trip_id, sequence);

CREATE TABLE IF NOT EXISTS public.trip_segments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id uuid NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  from_stop_id uuid NOT NULL REFERENCES public.trip_stops(id) ON DELETE CASCADE,
  to_stop_id uuid NOT NULL REFERENCES public.trip_stops(id) ON DELETE CASCADE,
  sequence integer NOT NULL,

  geometry jsonb NOT NULL,
  distance_km double precision NOT NULL,
  duration_seconds integer NOT NULL,
  style text NOT NULL DEFAULT 'Sport Mode',
  detour_level integer NOT NULL DEFAULT 0,
  avoid_highways boolean NOT NULL DEFAULT false,

  route_fingerprint text,
  generated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (trip_id, sequence)
);

CREATE INDEX IF NOT EXISTS idx_trip_segments_trip ON public.trip_segments(trip_id, sequence);

-- RLS — owner sieht eigene + group-shared, alle public sehen public trips
ALTER TABLE public.trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trip_stops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trip_segments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "trips_owner_full" ON public.trips;
CREATE POLICY "trips_owner_full" ON public.trips
  FOR ALL USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "trips_group_read" ON public.trips;
CREATE POLICY "trips_group_read" ON public.trips
  FOR SELECT USING (
    group_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.group_members
      WHERE group_id = trips.group_id AND user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "trips_public_read" ON public.trips;
CREATE POLICY "trips_public_read" ON public.trips
  FOR SELECT USING (is_public = true);

DROP POLICY IF EXISTS "trip_stops_via_trip" ON public.trip_stops;
CREATE POLICY "trip_stops_via_trip" ON public.trip_stops
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.trips
      WHERE trips.id = trip_stops.trip_id
        AND (trips.owner_id = auth.uid()
          OR trips.is_public = true
          OR (trips.group_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.group_members
            WHERE group_id = trips.group_id AND user_id = auth.uid()
          )))
    )
  );

DROP POLICY IF EXISTS "trip_segments_via_trip" ON public.trip_segments;
CREATE POLICY "trip_segments_via_trip" ON public.trip_segments
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.trips
      WHERE trips.id = trip_segments.trip_id
        AND (trips.owner_id = auth.uid()
          OR trips.is_public = true
          OR (trips.group_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.group_members
            WHERE group_id = trips.group_id AND user_id = auth.uid()
          )))
    )
  );

-- Trigger: updated_at + stop_count auto-update
CREATE OR REPLACE FUNCTION public.trips_update_timestamp()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trips_update_timestamp ON public.trips;
CREATE TRIGGER trips_update_timestamp
  BEFORE UPDATE ON public.trips
  FOR EACH ROW EXECUTE FUNCTION public.trips_update_timestamp();

CREATE OR REPLACE FUNCTION public.trips_refresh_stats(p_trip_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.trips
  SET stop_count = (SELECT COUNT(*) FROM public.trip_stops WHERE trip_id = p_trip_id),
      total_distance_km = COALESCE((SELECT SUM(distance_km) FROM public.trip_segments WHERE trip_id = p_trip_id), 0),
      total_duration_seconds = COALESCE((SELECT SUM(duration_seconds) FROM public.trip_segments WHERE trip_id = p_trip_id), 0)
  WHERE id = p_trip_id;
END $$;

COMMENT ON TABLE public.trips IS 'Multi-Stop Touren (Trip-Modus) — Task #3 vucko';
COMMENT ON TABLE public.trip_stops IS 'Wegpunkte einer Trip (overnight, lunch, photo, etc.)';
COMMENT ON TABLE public.trip_segments IS 'Live-generierte Routen zwischen aufeinanderfolgenden Stops';
