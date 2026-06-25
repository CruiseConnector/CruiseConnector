-- Fahrt-Fotos nachträglich setzen/ändern/entfernen können, OHNE die
-- Immutabilität der XP-/km-/Statistik-Felder aufzugeben.
--
-- ROOT CAUSE (2026-06-25): user_drive_sessions hatte RLS nur für SELECT +
-- INSERT, KEINE UPDATE-Policy. RLS verweigert per Default -> der Client-Call
-- updateDriveSessionPhoto (.update {photo_url}) traf 0 Zeilen OHNE Fehler ->
-- das Foto verschwand beim Neuladen (gespeicherte Routen / zuletzt gefahren).
--
-- Sicher + minimal: UPDATE nur auf EIGENE Zeilen (RLS using/with check
-- auth.uid() = user_id) UND nur auf die Spalte photo_url (Spalten-GRANT).
-- xp_awarded/distance_km/etc. bleiben damit unveraenderbar (kein Spalten-Grant
-- -> "permission denied for column"), die Sessions bleiben die immutable Quelle
-- fuer XP/Level. Der AFTER-INSERT-Trigger (Profil-Totals) feuert NICHT bei
-- UPDATE -> ein Foto-Update veraendert keine Statistik.

drop policy if exists "Users update own drive session photo"
  on public.user_drive_sessions;
create policy "Users update own drive session photo"
  on public.user_drive_sessions
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

revoke update on public.user_drive_sessions from authenticated;
grant update (photo_url) on public.user_drive_sessions to authenticated;
