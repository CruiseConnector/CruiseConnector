-- 2026-08-28 (Fehler 8, Community-Routenkarte): Die geteilte Route soll das
-- Hoechsttempo der Fahrt zeigen. Bisher lag das Tempo NUR in
-- user_drive_sessions des Besitzers, und dessen Zeilen sind fuer fremde
-- Betrachter nicht lesbar. Deshalb bekommt routes eine eigene Spalte, die
-- der Client beim Speichern einer GEFAHRENEN Route befuellt.
--
-- Alte Zeilen bleiben null, die Anzeige laesst die Tempo-Kachel dann weg.
-- RLS und Grants bleiben unveraendert.
alter table public.routes
  add column if not exists top_speed_kmh numeric;

comment on column public.routes.top_speed_kmh is
  '2026-08-28: Hoechsttempo der Fahrt in km/h, gesetzt beim Speichern einer '
  'gefahrenen Route. Null bei geplanten oder alten Routen; die Anzeige laesst '
  'die Kachel dann weg.';
