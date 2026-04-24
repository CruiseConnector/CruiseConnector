-- ============================================================================
-- Cruise-Groups: erweitert die bestehende `groups`/`group_members` um
-- Live-Routing, Rollen und Realtime-Positions-Tracking.
-- ============================================================================

-- 1) groups: Route, Startpunkt, Sichtbarkeit, aktiver Status
ALTER TABLE groups
  ADD COLUMN IF NOT EXISTS description       text,
  ADD COLUMN IF NOT EXISTS route_data        jsonb,
  ADD COLUMN IF NOT EXISTS start_location    jsonb,
  ADD COLUMN IF NOT EXISTS is_public         boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS is_active         boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS max_people        integer NOT NULL DEFAULT 10,
  ADD COLUMN IF NOT EXISTS start_time        timestamptz,
  ADD COLUMN IF NOT EXISTS activated_at      timestamptz;

-- 2) group_members: Rolle + Live-Position
DO $$ BEGIN
  CREATE TYPE group_member_role AS ENUM ('owner', 'driver', 'passenger');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE group_members
  ADD COLUMN IF NOT EXISTS role             group_member_role NOT NULL DEFAULT 'passenger',
  ADD COLUMN IF NOT EXISTS current_lat      double precision,
  ADD COLUMN IF NOT EXISTS current_lng      double precision,
  ADD COLUMN IF NOT EXISTS last_updated_at  timestamptz;

-- Ersteller der Gruppe automatisch zum Owner machen (Trigger)
CREATE OR REPLACE FUNCTION set_owner_on_group_insert() RETURNS trigger AS $$
BEGIN
  INSERT INTO group_members (group_id, user_id, role)
  VALUES (NEW.id, NEW.created_by, 'owner')
  ON CONFLICT (group_id, user_id) DO UPDATE SET role = 'owner';
  RETURN NEW;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_group_owner ON groups;
CREATE TRIGGER trg_group_owner AFTER INSERT ON groups
  FOR EACH ROW EXECUTE FUNCTION set_owner_on_group_insert();

-- 3) RLS-Erweiterungen
DROP POLICY IF EXISTS "Creator kann Gruppe updaten" ON groups;
CREATE POLICY "Owner kann Gruppe updaten" ON groups FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM group_members gm
    WHERE gm.group_id = groups.id
      AND gm.user_id  = auth.uid()
      AND gm.role     = 'owner'
  )
);

-- Member darf eigene Rolle (driver/passenger) + Position updaten;
-- Owner darf Rollen anderer anpassen.
DROP POLICY IF EXISTS "Member kann sich updaten" ON group_members;
CREATE POLICY "Member kann sich updaten" ON group_members FOR UPDATE USING (
  auth.uid() = user_id
  OR EXISTS (
    SELECT 1 FROM group_members gm
    WHERE gm.group_id = group_members.group_id
      AND gm.user_id  = auth.uid()
      AND gm.role     = 'owner'
  )
);

-- 4) Realtime einschalten
ALTER PUBLICATION supabase_realtime ADD TABLE groups;
ALTER PUBLICATION supabase_realtime ADD TABLE group_members;

-- 5) Index für Live-Tracking-Queries
CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(group_id);
