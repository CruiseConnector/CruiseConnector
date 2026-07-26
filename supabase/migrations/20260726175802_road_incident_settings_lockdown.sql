-- KRITISCH: road_incident_settings wurde ohne RLS angelegt und erbte die
-- Standard-Rechte fuer anon/authenticated — inklusive UPDATE. Damit haette
-- jeder eingeloggte Nutzer saemtliche Schwellwerte (Tageslimit, Mindest-
-- abstand, Ortsradius, Sperrgrenzen) selbst setzen und den kompletten
-- Missbrauchsschutz mit einem einzigen Request aushebeln koennen.
--
-- Die Tabelle ist reine Serverkonfiguration; kein Client hat dort etwas zu
-- suchen — auch nicht lesend (sonst kennt ein Angreifer die exakten Grenzen).
alter table public.road_incident_settings enable row level security;
revoke all on public.road_incident_settings from anon, authenticated;
-- Keine Policy = kein Zugriff. Gelesen wird sie ausschliesslich aus den
-- SECURITY-DEFINER-Funktionen, die als Eigentuemer laufen.

-- Gegenprobe fuer den Rest: auch road_reporter_stats darf nur lesbar sein.
revoke insert, update, delete, truncate, references, trigger
  on public.road_reporter_stats from anon, authenticated;;
