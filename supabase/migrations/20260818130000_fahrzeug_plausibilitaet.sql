-- 2026-08-18 (Defekt 4): Plausibilitaetsgrenzen fuer Fahrzeugdaten.
--
-- Ausgangslage (gemessen am 18.08. in der Produktivdatenbank): Ein Skoda
-- Fabia mit 1.100 PS und 0-100 in 1,2 Sekunden, eingetragen am 17.08. um
-- 22:03. Das Eingabefeld nahm jede Zahl bis 1999 an, und serverseitig gab es
-- gar keine Pruefung. Solche Werte verderben jede Garagen-Statistik.
--
-- Der Client prueft dieselben Grenzen (lib/domain/fahrzeug_grenzen.dart).
-- Diese Constraints sind die zweite Verteidigungslinie: sie gelten auch fuer
-- alte App-Versionen, die installiert bleiben, und fuer direkte API-Zugriffe.
--
-- Die eine verletzende Zeile wurde vorher auf Werkswerte korrigiert
-- (95 PS, 10,6 s - Fabia IV 1.0 TSI, von Vucko entschieden).
-- Geprueft: keine weitere Zeile verletzt die Grenzen.

alter table public.profile_vehicles
  drop constraint if exists profile_vehicles_horsepower_plausibel;
alter table public.profile_vehicles
  add constraint profile_vehicles_horsepower_plausibel
  check (horsepower is null or (horsepower >= 1 and horsepower <= 1500));

alter table public.profile_vehicles
  drop constraint if exists profile_vehicles_top_speed_plausibel;
alter table public.profile_vehicles
  add constraint profile_vehicles_top_speed_plausibel
  check (top_speed is null or (top_speed >= 1 and top_speed <= 400));

alter table public.profile_vehicles
  drop constraint if exists profile_vehicles_zero_to_hundred_plausibel;
alter table public.profile_vehicles
  add constraint profile_vehicles_zero_to_hundred_plausibel
  check (zero_to_hundred_seconds is null
         or (zero_to_hundred_seconds >= 1.5 and zero_to_hundred_seconds <= 30));
