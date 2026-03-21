-- ============================================================
-- VOLLSTÄNDIGE Backend-Migration
-- Enthält ALLES was nach init + profiles + social_features fehlt:
-- FKs, RPC, Gamification, Comments, Reposts, Notifications, Indexes
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. PROFILES: Gamification-Spalten + öffentlich lesbar
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS level int DEFAULT 1,
  ADD COLUMN IF NOT EXISTS total_km float DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_routes int DEFAULT 0,
  ADD COLUMN IF NOT EXISTS badges jsonb DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS bio text,
  ADD COLUMN IF NOT EXISTS avatar_url text,
  ADD COLUMN IF NOT EXISTS follower_count int DEFAULT 0,
  ADD COLUMN IF NOT EXISTS following_count int DEFAULT 0;

-- Profile öffentlich lesbar machen (nötig für Social Features)
DROP POLICY IF EXISTS "User sieht eigenes Profil" ON public.profiles;
DROP POLICY IF EXISTS "Profile sind öffentlich lesbar" ON public.profiles;
CREATE POLICY "Profile sind öffentlich lesbar"
  ON public.profiles FOR SELECT
  USING (true);


-- ─────────────────────────────────────────────────────────────
-- 2. ROUTES: Erweitern + RLS fixen
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public.routes
  ADD COLUMN IF NOT EXISTS rating int,
  ADD COLUMN IF NOT EXISTS driven_km float;

DROP POLICY IF EXISTS "User sieht eigene Routen" ON public.routes;
DROP POLICY IF EXISTS "User speichert eigene Routen" ON public.routes;
DROP POLICY IF EXISTS "User löscht eigene Routen" ON public.routes;
DROP POLICY IF EXISTS "Öffentliche bewertete Routen sind lesbar" ON public.routes;
DROP POLICY IF EXISTS "User kann eigene Routen updaten" ON public.routes;

CREATE POLICY "User sieht eigene Routen"
  ON public.routes FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Öffentliche bewertete Routen sind lesbar"
  ON public.routes FOR SELECT
  USING (rating IS NOT NULL AND rating >= 3);

CREATE POLICY "User speichert eigene Routen"
  ON public.routes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "User kann eigene Routen updaten"
  ON public.routes FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "User löscht eigene Routen"
  ON public.routes FOR DELETE
  USING (auth.uid() = user_id);


-- ─────────────────────────────────────────────────────────────
-- 3. FOREIGN KEYS zu profiles (nötig für PostgREST !fkey joins)
-- ─────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'posts_user_id_profiles_fkey' AND table_name = 'posts'
  ) THEN
    ALTER TABLE posts
      ADD CONSTRAINT posts_user_id_profiles_fkey
      FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'notifications_from_user_id_profiles_fkey' AND table_name = 'notifications'
  ) THEN
    ALTER TABLE notifications
      ADD CONSTRAINT notifications_from_user_id_profiles_fkey
      FOREIGN KEY (from_user_id) REFERENCES profiles(id) ON DELETE CASCADE;
  END IF;
END $$;


-- ─────────────────────────────────────────────────────────────
-- 4. LIKES RPC (increment/decrement)
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION increment_likes(post_id_param uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE posts SET likes_count = likes_count + 1 WHERE id = post_id_param;
END;
$$;

CREATE OR REPLACE FUNCTION decrement_likes(post_id_param uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE posts SET likes_count = GREATEST(likes_count - 1, 0) WHERE id = post_id_param;
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- 5. COMMENTS Tabelle + RPC
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now(),
  post_id uuid REFERENCES posts(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  content text NOT NULL
);

ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'comments' AND policyname = 'Comments sind öffentlich lesbar') THEN
    CREATE POLICY "Comments sind öffentlich lesbar" ON comments FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'comments' AND policyname = 'User kann kommentieren') THEN
    CREATE POLICY "User kann kommentieren" ON comments FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'comments' AND policyname = 'User kann eigene Comments löschen') THEN
    CREATE POLICY "User kann eigene Comments löschen" ON comments FOR DELETE USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'comments_user_id_profiles_fkey' AND table_name = 'comments'
  ) THEN
    ALTER TABLE comments
      ADD CONSTRAINT comments_user_id_profiles_fkey
      FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION increment_comments(post_id_param uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE posts SET comments_count = comments_count + 1 WHERE id = post_id_param;
END;
$$;

CREATE OR REPLACE FUNCTION decrement_comments(post_id_param uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE posts SET comments_count = GREATEST(comments_count - 1, 0) WHERE id = post_id_param;
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- 6. REPOSTS Tabelle + RPC (NEU!)
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.reposts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now(),
  post_id uuid REFERENCES posts(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  UNIQUE(post_id, user_id)
);

ALTER TABLE public.reposts ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'reposts' AND policyname = 'Reposts sind öffentlich lesbar') THEN
    CREATE POLICY "Reposts sind öffentlich lesbar" ON reposts FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'reposts' AND policyname = 'User kann reposten') THEN
    CREATE POLICY "User kann reposten" ON reposts FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'reposts' AND policyname = 'User kann Repost entfernen') THEN
    CREATE POLICY "User kann Repost entfernen" ON reposts FOR DELETE USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'reposts_user_id_profiles_fkey' AND table_name = 'reposts'
  ) THEN
    ALTER TABLE reposts
      ADD CONSTRAINT reposts_user_id_profiles_fkey
      FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION increment_reposts(post_id_param uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE posts SET reposts_count = reposts_count + 1 WHERE id = post_id_param;
END;
$$;

CREATE OR REPLACE FUNCTION decrement_reposts(post_id_param uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE posts SET reposts_count = GREATEST(reposts_count - 1, 0) WHERE id = post_id_param;
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- 7. NOTIFICATIONS: 'repost' Typ hinzufügen
-- ─────────────────────────────────────────────────────────────

-- Constraint erweitern um 'repost' Typ
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
  CHECK (type IN ('follow', 'like', 'comment', 'group_invite', 'repost'));


-- ─────────────────────────────────────────────────────────────
-- 8. FOLLOWS: Policy fix für upsert
-- ─────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "User kann eigene Follows updaten" ON follows;
CREATE POLICY "User kann eigene Follows updaten" ON follows
  FOR UPDATE USING (auth.uid() = follower_id);


-- ─────────────────────────────────────────────────────────────
-- 9. FOLLOWER/FOLLOWING Counts Trigger
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION update_follow_counts()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE profiles SET following_count = following_count + 1 WHERE id = NEW.follower_id;
    UPDATE profiles SET follower_count = follower_count + 1 WHERE id = NEW.following_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE profiles SET following_count = GREATEST(following_count - 1, 0) WHERE id = OLD.follower_id;
    UPDATE profiles SET follower_count = GREATEST(follower_count - 1, 0) WHERE id = OLD.following_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS on_follow_change ON follows;
CREATE TRIGGER on_follow_change
  AFTER INSERT OR DELETE ON follows
  FOR EACH ROW EXECUTE FUNCTION update_follow_counts();


-- ─────────────────────────────────────────────────────────────
-- 10. INDEXES für Performance
-- ─────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_profiles_username ON profiles USING btree (lower(username));
CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles USING btree (lower(email));
CREATE INDEX IF NOT EXISTS idx_routes_user_id ON routes (user_id);
CREATE INDEX IF NOT EXISTS idx_routes_user_created ON routes (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts (user_id);
CREATE INDEX IF NOT EXISTS idx_posts_created ON posts (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows (follower_id);
CREATE INDEX IF NOT EXISTS idx_follows_following ON follows (following_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_comments_post ON comments (post_id, created_at);
CREATE INDEX IF NOT EXISTS idx_reposts_user ON reposts (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reposts_post ON reposts (post_id);
