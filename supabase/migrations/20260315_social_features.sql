-- ============================================================
-- Social Features: Posts, Follows, Groups, Notifications
-- ============================================================

-- 1. Posts table
CREATE TABLE IF NOT EXISTS posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  content text NOT NULL,
  likes_count int DEFAULT 0,
  reposts_count int DEFAULT 0,
  comments_count int DEFAULT 0
);

ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Posts sind öffentlich lesbar" ON posts FOR SELECT USING (true);
CREATE POLICY "User kann eigene Posts erstellen" ON posts FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "User kann eigene Posts löschen" ON posts FOR DELETE USING (auth.uid() = user_id);
CREATE POLICY "User kann eigene Posts updaten" ON posts FOR UPDATE USING (auth.uid() = user_id);

-- 2. Follows table
CREATE TABLE IF NOT EXISTS follows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now(),
  follower_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  following_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  status text DEFAULT 'accepted' CHECK (status IN ('pending', 'accepted')),
  UNIQUE(follower_id, following_id)
);

ALTER TABLE follows ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Follows sind öffentlich lesbar" ON follows FOR SELECT USING (true);
CREATE POLICY "User kann folgen" ON follows FOR INSERT WITH CHECK (auth.uid() = follower_id);
CREATE POLICY "User kann entfolgen" ON follows FOR DELETE USING (auth.uid() = follower_id);
CREATE POLICY "User kann eigene Follows updaten" ON follows FOR UPDATE USING (auth.uid() = following_id);

-- 3. Groups table
CREATE TABLE IF NOT EXISTS groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  name text NOT NULL,
  route_name text,
  stats text,
  time_location text,
  description text
);

ALTER TABLE groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Gruppen sind öffentlich lesbar" ON groups FOR SELECT USING (true);
CREATE POLICY "User kann Gruppen erstellen" ON groups FOR INSERT WITH CHECK (auth.uid() = created_by);
CREATE POLICY "Creator kann Gruppe updaten" ON groups FOR UPDATE USING (auth.uid() = created_by);
CREATE POLICY "Creator kann Gruppe löschen" ON groups FOR DELETE USING (auth.uid() = created_by);

-- 4. Group members table
CREATE TABLE IF NOT EXISTS group_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now(),
  group_id uuid REFERENCES groups(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  UNIQUE(group_id, user_id)
);

ALTER TABLE group_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Mitglieder sind öffentlich lesbar" ON group_members FOR SELECT USING (true);
CREATE POLICY "User kann beitreten" ON group_members FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "User kann austreten" ON group_members FOR DELETE USING (auth.uid() = user_id);

-- 5. Post likes table
CREATE TABLE IF NOT EXISTS post_likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now(),
  post_id uuid REFERENCES posts(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  UNIQUE(post_id, user_id)
);

ALTER TABLE post_likes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Likes sind öffentlich lesbar" ON post_likes FOR SELECT USING (true);
CREATE POLICY "User kann liken" ON post_likes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "User kann unlike" ON post_likes FOR DELETE USING (auth.uid() = user_id);

-- 6. Notifications table
CREATE TABLE IF NOT EXISTS notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  from_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  type text NOT NULL CHECK (type IN ('follow', 'like', 'comment', 'group_invite')),
  read boolean DEFAULT false,
  reference_id uuid
);

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "User sieht eigene Notifications" ON notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "System kann Notifications erstellen" ON notifications FOR INSERT WITH CHECK (true);
CREATE POLICY "User kann eigene als gelesen markieren" ON notifications FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "User kann eigene löschen" ON notifications FOR DELETE USING (auth.uid() = user_id);

-- 7. Add avatar_url and bio to profiles
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS bio text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS avatar_url text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS follower_count int DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS following_count int DEFAULT 0;
