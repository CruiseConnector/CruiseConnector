-- 2026-07-25 (Review-Fund, kritisch): road_incidents war zu offen.
--
-- Problem 1 — UPDATE auf ALLE Spalten: die Policy ri_update_own beschränkt
-- zwar auf eigene Zeilen, aber innerhalb der eigenen Zeile durfte der Melder
-- per rohem PostgREST-Call alles überschreiben: expires_at (Meldung ewig
-- haltbar), confirmed_count/dismissed_count (Zähler fälschen), active
-- (nach 3 "weg"-Stimmen einfach wieder anschalten), lat/lng/type (Meldung
-- nachträglich verschieben/umwidmen). Das umgeht das komplette Vote-/TTL-
-- System. Der Client braucht echt NUR die Stau-Ausdehnung — also
-- column-scoped GRANT auf genau diese zwei Spalten (gleiches Muster wie bei
-- user_drive_sessions).
--
-- Problem 2 — anon: Policies ohne `to authenticated` gelten für PUBLIC, d.h.
-- der anon-Key konnte alle Live-Meldungen lesen und (mit gefälschtem
-- reported_by nicht, aber überhaupt) auf der Tabelle operieren. Meldungen
-- sind Positionsdaten von Nutzern — die gehören hinter Login.

-- ── 1. UPDATE hart auf die Stau-Ausdehnung begrenzen ────────────────────
revoke update on public.road_incidents from anon;
revoke update on public.road_incidents from authenticated;
grant update (jam_end_lat, jam_end_lng) on public.road_incidents to authenticated;

-- ── 2. Policies auf eingeloggte Nutzer einschränken ─────────────────────
drop policy if exists ri_select on public.road_incidents;
drop policy if exists ri_insert on public.road_incidents;
drop policy if exists ri_update_own on public.road_incidents;

create policy ri_select on public.road_incidents
  for select to authenticated
  using (active and expires_at > now());

create policy ri_insert on public.road_incidents
  for insert to authenticated
  with check (reported_by = auth.uid());

create policy ri_update_own on public.road_incidents
  for update to authenticated
  using (reported_by = auth.uid())
  with check (reported_by = auth.uid());

drop policy if exists riv_own on public.road_incident_votes;
create policy riv_own on public.road_incident_votes
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── 3. expires_at serverseitig deckeln ──────────────────────────────────
-- expires_at wird beim INSERT vom Client gesetzt (TTL pro Typ). Ohne Grenze
-- könnte ein manipulierter Client eine Meldung praktisch unbegrenzt
-- stehenlassen. Max-TTL = 24h (Baustelle, der längste legitime Wert) plus
-- 1h Puffer für Uhr-Abweichungen.
alter table public.road_incidents
  drop constraint if exists road_incidents_expires_sane;
alter table public.road_incidents
  add constraint road_incidents_expires_sane
  check (expires_at > created_at and expires_at <= created_at + interval '25 hours');
