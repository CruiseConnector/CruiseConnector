-- Post-Sichtbarkeit: 'public' (für alle) oder 'followers' (nur Follower)
ALTER TABLE posts ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'public'
  CHECK (visibility IN ('public', 'followers'));
