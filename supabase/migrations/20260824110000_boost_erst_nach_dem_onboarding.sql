-- 2026-08-24: Der Boost startet ERST nach dem Onboarding, nicht sofort.
--
-- Vucko, kurz nach der Auslieferung von 20260824100000:
--   "Also der boost soll nicht bis 30. August laufen, sondern sich erst
--    aktivieren, wenn sie das Tutorial beziehungsweise das On Boarding
--    abgeschlossen haben. Das soll aber jede Person sein. [...] davor
--    aktivieren das macht keinen Sinn."
--
-- Er hat recht, und der Fehler war meiner. 20260824100000 hat allen 183
-- Profilen starter_bonus_ende = now() + 7 Tage gesetzt. Damit lief die
-- Doppel-XP-Woche fuer Leute, die den Build noch gar nicht haben: bis sie
-- aktualisieren, waere die Woche abgelaufen, ohne dass sie eine einzige
-- Fahrt damit gemacht haetten. Das Geschenk waere verpufft.
--
-- KORREKTUR: starter_bonus_ende -> NULL fuer alle.
-- Der Client setzt es selbst, sobald das Onboarding steht
-- (starter_aufgaben_service.dart:469-471:
--  `if (boostErreicht && _bonusEnde == null && !_paketVergeben)`).
-- Damit startet die Woche genau dann, wenn sie etwas wert ist, und zwar
-- fuer JEDE Person - das war Vuckos zweite Bedingung.
--
-- DIE ABZEICHEN BLEIBEN. badge_15 "Gruendungszeit" und badge_16 "Startklar"
-- sind vergeben und werden NICHT zurueckgenommen. Grund: profiles.badges ist
-- seit dem 06.05. bewusst append-only (Migration 2026050605, Waechter
-- preserve_profile_badges). Ein Entziehen wuerde diesen Schutz brechen, und
-- Abzeichen laufen anders als der Boost nicht ab - Vuckos Einwand galt
-- ausdruecklich der Laufzeit, nicht den Abzeichen ("dass halt jeder ein
-- Badge bekommt" steht unveraendert).
--
-- Der Waechter trg_guard_starter_bonus_ende behindert nicht: er greift nur
-- bei auth.uid() is not null, im Migrationslauf ist auth.uid() NULL.
-- Danach kann jeder Client sein Bonus-Ende genau EINMAL setzen, und der
-- Waechter schuetzt es wieder gegen ein zweites Geraet.

update public.profiles
   set starter_bonus_ende = null
 where starter_bonus_ende is not null;

do $$
declare
  v_bonus int;
  v_b15   int;
begin
  select count(starter_bonus_ende),
         count(*) filter (where badges @> '["badge_15"]')
    into v_bonus, v_b15
    from public.profiles;

  if v_bonus <> 0 then
    raise exception 'Es laeuft noch bei % Profilen eine Bonuswoche.', v_bonus;
  end if;
  if v_b15 = 0 then
    raise exception 'badge_15 ist verlorengegangen - das war nicht beabsichtigt.';
  end if;

  raise notice 'Bonuswochen zurueckgesetzt. badge_15 unveraendert bei % Profilen.', v_b15;
end $$;
