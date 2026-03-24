-- ============================================================
-- CRUISECONNECT — KOMPLETTES DATENBANK-SETUP
-- ============================================================
-- Dieses Skript enthält ALLES was die App braucht.
-- Kann sicher mehrfach ausgeführt werden (idempotent).
--
-- ANLEITUNG:
-- 1. Gehe zu Supabase Dashboard → SQL Editor
-- 2. Kopiere dieses gesamte Skript
-- 3. Klicke "Run"
-- 4. Fertig!
-- ============================================================


-- ═══════════════════════════════════════════════════════════════
-- SCHRITT 1: TABELLEN
-- ═══════════════════════════════════════════════════════════════

-- 1a) Routes Tabelle
CREATE TABLE IF NOT EXISTS public.routes (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at timestamptz DEFAULT now(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  name text,
  style text,
  distance_target int,
  distance_actual float,
  geometry jsonb,
  route_type text,
  duration_seconds float,
  rating int,
  driven_km float
);

-- Fehlende Spalten nachrüsten (falls Tabelle schon existiert)
ALTER TABLE public.routes ADD COLUMN IF NOT EXISTS name text;
ALTER TABLE public.routes ADD COLUMN IF NOT EXISTS route_type text;
ALTER TABLE public.routes ADD COLUMN IF NOT EXISTS duration_seconds float;
ALTER TABLE public.routes ADD COLUMN IF NOT EXISTS rating int;
ALTER TABLE public.routes ADD COLUMN IF NOT EXISTS driven_km float;

ALTER TABLE public.routes ENABLE ROW LEVEL SECURITY;


-- 1b) Profiles Tabelle
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text,
  username text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Fehlende Spalten nachrüsten
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS level int DEFAULT 1,
  ADD COLUMN IF NOT EXISTS total_km float DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_routes int DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_xp int DEFAULT 0,
  ADD COLUMN IF NOT EXISTS badges jsonb DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS bio text,
  ADD COLUMN IF NOT EXISTS avatar_url text,
  ADD COLUMN IF NOT EXISTS follower_count int DEFAULT 0,
  ADD COLUMN IF NOT EXISTS following_count int DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_private boolean NOT NULL DEFAULT false;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;


-- 1c) Posts Tabelle
CREATE TABLE IF NOT EXISTS public.posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  content text NOT NULL,
  likes_count int DEFAULT 0,
  reposts_count int DEFAULT 0,
  comments_count int DEFAULT 0
);

ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'public';
-- Constraint nur hinzufügen wenn noch nicht vorhanden
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'posts_visibility_check') THEN
    ALTER TABLE posts ADD CONSTRAINT posts_visibility_check CHECK (visibility IN ('public', 'followers'));
  END IF;
END $$;

ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;


-- 1d) Follows Tabelle
CREATE TABLE IF NOT EXISTS public.follows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now(),
  follower_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  following_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  status text DEFAULT 'accepted' CHECK (status IN ('pending', 'accepted')),
  UNIQUE(follower_id, following_id)
);

ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;


-- 1e) Groups Tabelle
CREATE TABLE IF NOT EXISTS public.groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  name text NOT NULL,
  route_name text,
  stats text,
  time_location text,
  description text
);

ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;


-- 1f) Group Members
CREATE TABLE IF NOT EXISTS public.group_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now(),
  group_id uuid REFERENCES groups(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  UNIQUE(group_id, user_id)
);

ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;


-- 1g) Post Likes
CREATE TABLE IF NOT EXISTS public.post_likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now(),
  post_id uuid REFERENCES posts(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  UNIQUE(post_id, user_id)
);

ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;


-- 1h) Comments
CREATE TABLE IF NOT EXISTS public.comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now(),
  post_id uuid REFERENCES posts(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  content text NOT NULL
);

ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;


-- 1i) Reposts
CREATE TABLE IF NOT EXISTS public.reposts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now(),
  post_id uuid REFERENCES posts(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  UNIQUE(post_id, user_id)
);

ALTER TABLE public.reposts ENABLE ROW LEVEL SECURITY;


-- 1j) Notifications
CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  from_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  type text NOT NULL,
  read boolean DEFAULT false,
  reference_id uuid
);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Notification type constraint (mit 'repost' Typ!)
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'notifications_type_check') THEN
    ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
      CHECK (type IN ('follow', 'like', 'comment', 'repost', 'group_invite'));
  END IF;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;


-- ═══════════════════════════════════════════════════════════════
-- SCHRITT 2: FOREIGN KEYS zu profiles (für PostgREST Joins)
-- ═══════════════════════════════════════════════════════════════

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'posts_user_id_profiles_fkey' AND table_name = 'posts'
  ) THEN
    ALTER TABLE posts ADD CONSTRAINT posts_user_id_profiles_fkey
      FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'comments_user_id_profiles_fkey' AND table_name = 'comments'
  ) THEN
    ALTER TABLE comments ADD CONSTRAINT comments_user_id_profiles_fkey
      FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'notifications_from_user_id_profiles_fkey' AND table_name = 'notifications'
  ) THEN
    ALTER TABLE notifications ADD CONSTRAINT notifications_from_user_id_profiles_fkey
      FOREIGN KEY (from_user_id) REFERENCES profiles(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'reposts_user_id_profiles_fkey' AND table_name = 'reposts'
  ) THEN
    ALTER TABLE reposts ADD CONSTRAINT reposts_user_id_profiles_fkey
      FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'follows_follower_id_profiles_fkey' AND table_name = 'follows'
  ) THEN
    ALTER TABLE follows ADD CONSTRAINT follows_follower_id_profiles_fkey
      FOREIGN KEY (follower_id) REFERENCES profiles(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'follows_following_id_profiles_fkey' AND table_name = 'follows'
  ) THEN
    ALTER TABLE follows ADD CONSTRAINT follows_following_id_profiles_fkey
      FOREIGN KEY (following_id) REFERENCES profiles(id) ON DELETE CASCADE;
  END IF;
END $$;


-- ═══════════════════════════════════════════════════════════════
-- SCHRITT 3: RLS POLICIES (Row Level Security)
-- ═══════════════════════════════════════════════════════════════

-- Profiles: öffentlich lesbar (nötig für Social Features)
DROP POLICY IF EXISTS "User sieht eigenes Profil" ON public.profiles;
DROP POLICY IF EXISTS "Profile sind öffentlich lesbar" ON public.profiles;
DROP POLICY IF EXISTS "User erstellt eigenes Profil" ON public.profiles;
DROP POLICY IF EXISTS "User aktualisiert eigenes Profil" ON public.profiles;

CREATE POLICY "Profile sind öffentlich lesbar" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "User erstellt eigenes Profil" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "User aktualisiert eigenes Profil" ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Routes
DROP POLICY IF EXISTS "User sieht eigene Routen" ON public.routes;
DROP POLICY IF EXISTS "User speichert eigene Routen" ON public.routes;
DROP POLICY IF EXISTS "User kann eigene Routen updaten" ON public.routes;
DROP POLICY IF EXISTS "User löscht eigene Routen" ON public.routes;
DROP POLICY IF EXISTS "Öffentliche bewertete Routen sind lesbar" ON public.routes;

CREATE POLICY "User sieht eigene Routen" ON public.routes FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Öffentliche bewertete Routen sind lesbar" ON public.routes FOR SELECT
  USING (auth.role() = 'authenticated' AND rating IS NOT NULL AND rating >= 3);
CREATE POLICY "User speichert eigene Routen" ON public.routes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "User kann eigene Routen updaten" ON public.routes FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "User löscht eigene Routen" ON public.routes FOR DELETE USING (auth.uid() = user_id);

-- Posts
DO $$ BEGIN
  DROP POLICY IF EXISTS "Posts sind öffentlich lesbar" ON posts;
  DROP POLICY IF EXISTS "User kann eigene Posts erstellen" ON posts;
  DROP POLICY IF EXISTS "User kann eigene Posts löschen" ON posts;
  DROP POLICY IF EXISTS "User kann eigene Posts updaten" ON posts;
  CREATE POLICY "Posts sind öffentlich lesbar" ON posts FOR SELECT USING (true);
  CREATE POLICY "User kann eigene Posts erstellen" ON posts FOR INSERT WITH CHECK (auth.uid() = user_id);
  CREATE POLICY "User kann eigene Posts löschen" ON posts FOR DELETE USING (auth.uid() = user_id);
  CREATE POLICY "User kann eigene Posts updaten" ON posts FOR UPDATE USING (auth.uid() = user_id);
END $$;

-- Follows
DO $$ BEGIN
  DROP POLICY IF EXISTS "Follows sind öffentlich lesbar" ON follows;
  DROP POLICY IF EXISTS "User kann folgen" ON follows;
  DROP POLICY IF EXISTS "User kann entfolgen" ON follows;
  DROP POLICY IF EXISTS "User kann eigene Follows updaten" ON follows;
  CREATE POLICY "Follows sind öffentlich lesbar" ON follows FOR SELECT USING (true);
  CREATE POLICY "User kann folgen" ON follows FOR INSERT WITH CHECK (auth.uid() = follower_id);
  CREATE POLICY "User kann entfolgen" ON follows FOR DELETE USING (auth.uid() = follower_id);
  CREATE POLICY "User kann eigene Follows updaten" ON follows FOR UPDATE USING (auth.uid() = follower_id);
END $$;

-- Groups
DO $$ BEGIN
  DROP POLICY IF EXISTS "Gruppen sind öffentlich lesbar" ON groups;
  DROP POLICY IF EXISTS "User kann Gruppen erstellen" ON groups;
  DROP POLICY IF EXISTS "Creator kann Gruppe updaten" ON groups;
  DROP POLICY IF EXISTS "Creator kann Gruppe löschen" ON groups;
  CREATE POLICY "Gruppen sind öffentlich lesbar" ON groups FOR SELECT USING (true);
  CREATE POLICY "User kann Gruppen erstellen" ON groups FOR INSERT WITH CHECK (auth.uid() = created_by);
  CREATE POLICY "Creator kann Gruppe updaten" ON groups FOR UPDATE USING (auth.uid() = created_by);
  CREATE POLICY "Creator kann Gruppe löschen" ON groups FOR DELETE USING (auth.uid() = created_by);
END $$;

-- Group Members
DO $$ BEGIN
  DROP POLICY IF EXISTS "Mitglieder sind öffentlich lesbar" ON group_members;
  DROP POLICY IF EXISTS "User kann beitreten" ON group_members;
  DROP POLICY IF EXISTS "User kann austreten" ON group_members;
  CREATE POLICY "Mitglieder sind öffentlich lesbar" ON group_members FOR SELECT USING (true);
  CREATE POLICY "User kann beitreten" ON group_members FOR INSERT WITH CHECK (auth.uid() = user_id);
  CREATE POLICY "User kann austreten" ON group_members FOR DELETE USING (auth.uid() = user_id);
END $$;

-- Post Likes
DO $$ BEGIN
  DROP POLICY IF EXISTS "Likes sind öffentlich lesbar" ON post_likes;
  DROP POLICY IF EXISTS "User kann liken" ON post_likes;
  DROP POLICY IF EXISTS "User kann unlike" ON post_likes;
  CREATE POLICY "Likes sind öffentlich lesbar" ON post_likes FOR SELECT USING (true);
  CREATE POLICY "User kann liken" ON post_likes FOR INSERT WITH CHECK (auth.uid() = user_id);
  CREATE POLICY "User kann unlike" ON post_likes FOR DELETE USING (auth.uid() = user_id);
END $$;

-- Comments
DO $$ BEGIN
  DROP POLICY IF EXISTS "Comments sind öffentlich lesbar" ON comments;
  DROP POLICY IF EXISTS "User kann kommentieren" ON comments;
  DROP POLICY IF EXISTS "User kann eigene Comments löschen" ON comments;
  CREATE POLICY "Comments sind öffentlich lesbar" ON comments FOR SELECT USING (true);
  CREATE POLICY "User kann kommentieren" ON comments FOR INSERT WITH CHECK (auth.uid() = user_id);
  CREATE POLICY "User kann eigene Comments löschen" ON comments FOR DELETE USING (auth.uid() = user_id);
END $$;

-- Reposts
DO $$ BEGIN
  DROP POLICY IF EXISTS "Reposts sind öffentlich lesbar" ON reposts;
  DROP POLICY IF EXISTS "User kann reposten" ON reposts;
  DROP POLICY IF EXISTS "User kann Repost entfernen" ON reposts;
  CREATE POLICY "Reposts sind öffentlich lesbar" ON reposts FOR SELECT USING (true);
  CREATE POLICY "User kann reposten" ON reposts FOR INSERT WITH CHECK (auth.uid() = user_id);
  CREATE POLICY "User kann Repost entfernen" ON reposts FOR DELETE USING (auth.uid() = user_id);
END $$;

-- Notifications
DO $$ BEGIN
  DROP POLICY IF EXISTS "User sieht eigene Notifications" ON notifications;
  DROP POLICY IF EXISTS "System kann Notifications erstellen" ON notifications;
  DROP POLICY IF EXISTS "User kann eigene als gelesen markieren" ON notifications;
  DROP POLICY IF EXISTS "User kann eigene löschen" ON notifications;
  CREATE POLICY "User sieht eigene Notifications" ON notifications FOR SELECT USING (auth.uid() = user_id);
  CREATE POLICY "System kann Notifications erstellen" ON notifications FOR INSERT WITH CHECK (true);
  CREATE POLICY "User kann eigene als gelesen markieren" ON notifications FOR UPDATE USING (auth.uid() = user_id);
  CREATE POLICY "User kann eigene löschen" ON notifications FOR DELETE USING (auth.uid() = user_id);
END $$;


-- ═══════════════════════════════════════════════════════════════
-- SCHRITT 4: TRIGGER (Automatisches Profil beim Signup)
-- ═══════════════════════════════════════════════════════════════

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


-- ═══════════════════════════════════════════════════════════════
-- SCHRITT 5: RPC FUNKTIONEN (Likes, Comments, Reposts Zähler)
-- ═══════════════════════════════════════════════════════════════

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


-- ═══════════════════════════════════════════════════════════════
-- SCHRITT 6: FOLLOWER COUNT TRIGGER
-- ═══════════════════════════════════════════════════════════════

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


-- ═══════════════════════════════════════════════════════════════
-- SCHRITT 7: INDEXES (Performance)
-- ═══════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_profiles_username ON profiles USING btree (lower(username));
CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles USING btree (lower(email));
CREATE INDEX IF NOT EXISTS idx_routes_user_id ON routes (user_id);
CREATE INDEX IF NOT EXISTS idx_routes_user_created ON routes (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts (user_id);
CREATE INDEX IF NOT EXISTS idx_posts_created ON posts (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows (follower_id);
CREATE INDEX IF NOT EXISTS idx_follows_following ON follows (following_id);
CREATE INDEX IF NOT EXISTS idx_follows_follower_following ON follows (follower_id, following_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_comments_post ON comments (post_id, created_at);
CREATE INDEX IF NOT EXISTS idx_reposts_user ON reposts (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reposts_post ON reposts (post_id);


-- ═══════════════════════════════════════════════════════════════
-- FERTIG! Alle Tabellen, Policies, Trigger und Indexes sind aktiv.
-- ═══════════════════════════════════════════════════════════════
