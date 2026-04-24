-- ─────────────────────────────────────────────────────────────
-- Kommentar-Threads + Kommentar-Likes
-- ─────────────────────────────────────────────────────────────

-- 1) parent_comment_id für Threads
ALTER TABLE public.comments
  ADD COLUMN IF NOT EXISTS parent_comment_id uuid
    REFERENCES public.comments(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_comments_parent
  ON public.comments (parent_comment_id, created_at);

-- 2) likes_count-Spalte für Kommentare
ALTER TABLE public.comments
  ADD COLUMN IF NOT EXISTS likes_count integer NOT NULL DEFAULT 0;

-- 3) comment_likes-Tabelle
CREATE TABLE IF NOT EXISTS public.comment_likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now(),
  comment_id uuid REFERENCES public.comments(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  UNIQUE (comment_id, user_id)
);

ALTER TABLE public.comment_likes ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'comment_likes' AND policyname = 'Comment-Likes öffentlich lesbar') THEN
    CREATE POLICY "Comment-Likes öffentlich lesbar" ON public.comment_likes FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'comment_likes' AND policyname = 'User kann eigene Comment-Likes erstellen') THEN
    CREATE POLICY "User kann eigene Comment-Likes erstellen" ON public.comment_likes
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'comment_likes' AND policyname = 'User kann eigene Comment-Likes löschen') THEN
    CREATE POLICY "User kann eigene Comment-Likes löschen" ON public.comment_likes
      FOR DELETE USING (auth.uid() = user_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_comment_likes_comment
  ON public.comment_likes (comment_id);
CREATE INDEX IF NOT EXISTS idx_comment_likes_user
  ON public.comment_likes (user_id);

-- 4) RPCs für Like-Count
CREATE OR REPLACE FUNCTION public.increment_comment_likes(comment_id_param uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.comments
     SET likes_count = likes_count + 1
   WHERE id = comment_id_param;
END;
$$;

CREATE OR REPLACE FUNCTION public.decrement_comment_likes(comment_id_param uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.comments
     SET likes_count = GREATEST(likes_count - 1, 0)
   WHERE id = comment_id_param;
END;
$$;
