-- 2026-08-28, Nachtrag zu Fehler 6: Die Supabase-Default-Privileges geben
-- neuen Funktionen EXECUTE fuer anon und authenticated. Trigger-Funktionen
-- feuern ohne EXECUTE-Recht des Aufrufers — kein Client muss sie je direkt
-- aufrufen koennen. Und das Stummschalten ist nur fuer Angemeldete.
revoke all on function public.notify_on_feed_post() from public, anon, authenticated;
revoke all on function public.notify_on_community_message() from public, anon, authenticated;
revoke all on function public.set_community_stumm(uuid, boolean) from anon;
