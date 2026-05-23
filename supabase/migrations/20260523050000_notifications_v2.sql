-- 2026-05-23 (vucko): Notifications v2
-- Erweitert die bestehende notifications-Tabelle um:
--   * payload JSONB (title, body, route, icon, deeplink)
--   * weather_recommendation type
--   * aggregate_count + aggregate_until (für Like-Batching)
-- Plus DB-Triggers die automatisch Notifications erzeugen bei:
--   * neuem Follow
--   * neuem Post-Like (gebatcht in 10-Min-Buckets)
--   * neuem Group-Member (Einladung)

BEGIN;

-- 1. Tabellen-Erweiterungen
ALTER TABLE notifications
  ADD COLUMN IF NOT EXISTS payload jsonb DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS aggregate_count integer DEFAULT 1,
  ADD COLUMN IF NOT EXISTS aggregate_until timestamptz;

-- Erweitere Type-Check um weather_recommendation + friend_request
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
  CHECK (type IN (
    'follow', 'like', 'comment', 'group_invite',
    'friend_request', 'weather_recommendation', 'trip_reminder',
    'group_ride_started', 'group_public_created', 'group_joined', 'repost'
  ));

-- Index für schnelle unread-Abfrage + Realtime
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
  ON notifications(user_id, read, created_at DESC)
  WHERE read = false;

-- 2. Trigger: neuer Follow → Notification
CREATE OR REPLACE FUNCTION public.notify_on_follow()
RETURNS TRIGGER AS $$
BEGIN
  -- Verhindere self-notifications + duplicate (z. B. wenn user re-folgt)
  IF NEW.follower_id = NEW.following_id THEN
    RETURN NEW;
  END IF;
  INSERT INTO notifications (user_id, from_user_id, type, reference_id, payload)
  VALUES (
    NEW.following_id,
    NEW.follower_id,
    'follow',
    NEW.id,
    jsonb_build_object('action', 'follow')
  )
  ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_follows_notify ON follows;
CREATE TRIGGER trg_follows_notify
  AFTER INSERT ON follows
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_follow();

-- 3. Trigger: neuer Like → Notification (mit 10-Min-Batching)
CREATE OR REPLACE FUNCTION public.notify_on_like()
RETURNS TRIGGER AS $$
DECLARE
  post_owner_id uuid;
  existing_notification_id uuid;
BEGIN
  SELECT user_id INTO post_owner_id FROM posts WHERE id = NEW.post_id;
  IF post_owner_id IS NULL OR post_owner_id = NEW.user_id THEN
    RETURN NEW;  -- kein self-like-notification
  END IF;
  -- Such existing unread aggregator für (post_id, owner) in last 10min
  SELECT id INTO existing_notification_id
  FROM notifications
  WHERE user_id = post_owner_id
    AND type = 'like'
    AND reference_id = NEW.post_id
    AND read = false
    AND created_at > NOW() - INTERVAL '10 minutes'
  ORDER BY created_at DESC
  LIMIT 1;

  IF existing_notification_id IS NOT NULL THEN
    -- Aggregiere: count hochzählen + Liker zur Liste
    UPDATE notifications
    SET aggregate_count = aggregate_count + 1,
        aggregate_until = NOW(),
        payload = jsonb_set(
          COALESCE(payload, '{}'::jsonb),
          '{additional_likers}',
          COALESCE(payload->'additional_likers', '[]'::jsonb) || to_jsonb(NEW.user_id::text)
        )
    WHERE id = existing_notification_id;
  ELSE
    INSERT INTO notifications (user_id, from_user_id, type, reference_id, payload, aggregate_until)
    VALUES (
      post_owner_id,
      NEW.user_id,
      'like',
      NEW.post_id,
      jsonb_build_object('action', 'like', 'post_id', NEW.post_id),
      NOW() + INTERVAL '10 minutes'
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_likes_notify ON post_likes;
CREATE TRIGGER trg_likes_notify
  AFTER INSERT ON post_likes
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_like();

-- 4. Trigger: neuer group_member → "group_invite" notification an den User
-- (Wenn group_invites-Tabelle später kommt, kann der hierfür angepasst werden)
CREATE OR REPLACE FUNCTION public.notify_on_group_join()
RETURNS TRIGGER AS $$
DECLARE
  inviter_id uuid;
  group_name text;
BEGIN
  -- Nur wenn invited_by != self
  SELECT name INTO group_name FROM groups WHERE id = NEW.group_id;
  -- Notification: someone added you to a group
  IF NEW.added_by IS NOT NULL AND NEW.added_by != NEW.user_id THEN
    INSERT INTO notifications (user_id, from_user_id, type, reference_id, payload)
    VALUES (
      NEW.user_id,
      NEW.added_by,
      'group_invite',
      NEW.group_id,
      jsonb_build_object(
        'action', 'group_invite',
        'group_id', NEW.group_id::text,
        'group_name', COALESCE(group_name, 'Gruppe')
      )
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Spalte 'added_by' optional zur group_members (wenn nicht existent)
ALTER TABLE group_members ADD COLUMN IF NOT EXISTS added_by uuid REFERENCES auth.users(id);

DROP TRIGGER IF EXISTS trg_group_members_notify ON group_members;
CREATE TRIGGER trg_group_members_notify
  AFTER INSERT ON group_members
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_group_join();

-- 5. Realtime aktivieren für notifications (für Live-Updates im Flutter)
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;

COMMIT;
