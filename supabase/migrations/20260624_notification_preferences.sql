-- 2026-06-24 (vucko): Opt-out Push-Präferenzen pro User.
--
-- Hintergrund: Die Notification-Toggles lagen bisher NUR lokal
-- (SharedPreferences) → die Edge-Function send-push konnte sie nicht sehen und
-- hat jeden Typ gepusht. Diese Spalte macht die Einstellungen server-lesbar.
--
-- Modell: leeres Objekt / fehlender Schlüssel = AKTIVIERT. Beim ersten „Erlauben"
-- ist also alles an; der Nutzer schaltet in den Einstellungen nur ab, was ihm zu
-- viel ist (Schlüssel wird dann auf false gesetzt). send-push (categoryForType)
-- und der Client (NotificationSettingsService) nutzen dieselben Schlüsselnamen:
--   follows, likes, reposts, comments, friend_requests, group_invites, daily_weather
alter table public.profiles
  add column if not exists notification_preferences jsonb not null
    default '{}'::jsonb;
