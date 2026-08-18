-- 2026-08-18 (Aufgabe 4.1, Vucko-Sprachnachricht 08 vom 16.08.):
-- "Gruendungs-Badge: Runterschrauben, dass man es nur einmal bekommt und
--  nicht alle fuenf Minuten."
--
-- URSACHE, gemessen in der Produktivdatenbank am 18.08.:
--   select count(*) filter (where badges @> '["badge_15"]') from profiles;
--   -> 0 von 151 Profilen. KEIN EINZIGES.
--
-- Die App vergibt badge_15 bei jedem Sync bedingungslos
-- (gamification_service.dart:838). Die Datenbank hat es aber jedes Mal
-- stillschweigend weggeworfen: `normalize_badge_ids` war eine hartkodierte
-- Whitelist, die nur badge_01..badge_10, badge_13 und badge_14 kannte. Beim
-- naechsten Sync fehlte das Badge also wieder im Profil, galt damit erneut als
-- "neu" - und das Verleih-Popup ging wieder auf. Bei jedem Tab-Wechsel auf die
-- Startseite (home_page.dart zaehlt dort den refreshKey hoch). Das ist Vuckos
-- "alle fuenf Minuten".
--
-- Betroffen war nicht nur badge_15, sondern ALLES ab badge_15 - also auch die
-- 14 neuen Badges aus der Testfahrt vom 15.08. Die wurden nie gespeichert.
--
-- LOESUNG: Die Whitelist wird durch eine Musterpruefung ersetzt. Damit gibt es
-- keine zweite Liste mehr, die man beim Anlegen eines Badges vergessen kann -
-- die Fehlerklasse verschwindet, statt nur dieser eine Fall repariert zu
-- werden. Der Schutzzweck bleibt: fremde oder kaputte Werte kommen weiterhin
-- nicht ins Profil, und die Sortierung ergibt sich aus der Nummer.
--
-- Verworfen: eine Katalog-Tabelle, aus der die Funktion liest. Sie waere
-- ebenfalls pflegeleicht, zwingt die Funktion aber von IMMUTABLE auf STABLE
-- und bringt eine Tabelle mit RLS-Bedarf mit. Fuer denselben Nutzen zu viel
-- bewegliche Teile.
create or replace function public.normalize_badge_ids(p_badges jsonb)
returns jsonb
language sql
immutable
set search_path to 'public'
as $function$
  with raw_badges(id) as (
    select
      case value
        when 'route_1' then 'badge_02'   -- Altbestand aus der ersten Fassung
        else value
      end
    from jsonb_array_elements_text(
      case
        when jsonb_typeof(coalesce(p_badges, '[]'::jsonb)) = 'array'
          then coalesce(p_badges, '[]'::jsonb)
        else '[]'::jsonb
      end
    )
  ),
  gueltige_badges as (
    select distinct
      id,
      (substring(id from 7))::int as sort_order
    from raw_badges
    where id ~ '^badge_[0-9]{2}$'
  )
  select coalesce(jsonb_agg(id order by sort_order), '[]'::jsonb)
  from gueltige_badges;
$function$;

-- Nachzug fuer die 151 Bestandsprofile: badge_15 einmal richtig eintragen.
-- Ohne diesen Schritt wuerde das Badge beim ersten Start nach dem Update noch
-- einmal mit Animation verliehen - was fuer sich genommen richtig waere, aber
-- diese Nutzer haben das Popup durch den Fehler bereits dutzende Male gesehen.
-- Der Trigger trg_preserve_profile_badges normalisiert das Ergebnis selbst.
--
-- Die anderen Badges (17-36) werden BEWUSST NICHT per SQL nachgetragen: die
-- sollen beim ersten Sync nach dem Update regulaer verdient und gefeiert
-- werden.
update public.profiles
set badges = coalesce(badges, '[]'::jsonb) || '["badge_15"]'::jsonb
where not (coalesce(badges, '[]'::jsonb) @> '["badge_15"]'::jsonb);
