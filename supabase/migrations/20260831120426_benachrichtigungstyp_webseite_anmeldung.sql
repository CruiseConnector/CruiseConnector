-- 2026-08-31 — Der neue Meldungstyp fuer Anmeldungen ueber die Webseite.
--
-- Beim ersten Probelauf hat die Pruefregel zugeschlagen und den Einbau
-- gestoppt, bevor irgendetwas Halbes live ging. Genau dafuer ist sie da.
--
-- Der Typ verhaelt sich wie 'monitor_alarm': Er beschreibt kein soziales
-- Ereignis und bringt Titel und Text in der Nutzlast selbst mit. send-push und
-- der Client rendern beide aus payload.title und payload.body; ohne einen
-- eigenen Zweig dort stuende nur "Benachrichtigung" auf dem Sperrbildschirm.

alter table public.notifications drop constraint if exists notifications_type_check;

alter table public.notifications add constraint notifications_type_check
  check (type = any (array[
    'follow', 'like', 'comment', 'group_invite', 'friend_request',
    'weather_recommendation', 'trip_reminder', 'group_ride_started',
    'group_public_created', 'group_joined', 'repost', 'monitor_alarm',
    'feed_post', 'community_message',
    'webseite_anmeldung'
  ]));
