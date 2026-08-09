-- ═══════════════════════════════════════════════════════════════════════════
-- Vier Schnappschuesse pro Tag statt zwei — 0, 6, 12 und 18 Uhr Ortszeit Wien
--
-- Auftrag Vucko 2026-08-09: „einmal um 6 uhr dann um 12 uhr dann um 18 uhr und
-- um 0 uhr die Daten aus der Datenbank holst. Ich will nicht das die datenbank
-- ueberlastet wird ... maximal 4 mal in 24 stunden."
--
-- WIE DIE OBERGRENZE ERZWUNGEN WIRD (das ist der Kern):
-- Nicht der Zeitplan deckelt, sondern der SLOT-SCHLUESSEL. admin_metric_snapshots
-- hat einen eindeutigen slot_key, und admin_monitor_take_snapshot() rechnet gar
-- nichts, wenn fuer den laufenden Slot schon eine Zeile existiert. Da ein Tag
-- exakt vier Slots hat (-00, -06, -12, -18), kann es pro Tag hoechstens vier
-- schwere Berechnungen geben — egal wie oft jemand die Funktion aufruft.
-- Genau diese Eigenschaft hat schon am 07.08. die Ueberlastung beendet.
--
-- WARUM DER CRON STUENDLICH LAEUFT UND NICHT VIERMAL:
-- pg_cron rechnet in UTC (cron.timezone = GMT). Wien ist im Sommer UTC+2, im
-- Winter UTC+1 — vier feste UTC-Zeiten wuerden im Winter um eine Stunde
-- verrutschen (5/11/17/23 statt 6/12/18/0). Der stuendliche Lauf trifft dagegen
-- ganzjaehrig genau die Wiener Zeiten, weil der Slot-Schluessel in Wiener Zeit
-- rechnet: Der erste Lauf INNERHALB eines Slots schreibt, alle weiteren steigen
-- sofort wieder aus. Der Ausstieg ist ein indizierter EXISTS auf eine winzige
-- Tabelle — 20 belanglose Aufrufe pro Tag gegen einen exakten Zeitpunkt.
-- Nebeneffekt, der uns entgegenkommt: Faellt ein Lauf aus (DB busy, Wartung),
-- holt ihn die naechste Stunde nach, statt den Slot sechs Stunden leer zu lassen.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.monitor_slot_key(at timestamptz default now())
returns text
language sql
immutable
set search_path to 'pg_catalog', 'pg_temp'
as $function$
  -- Sechs-Stunden-Fenster in Wiener Ortszeit: 0-5 -> '-00', 6-11 -> '-06',
  -- 12-17 -> '-12', 18-23 -> '-18'. Ganzzahlige Division, deshalb der ::int.
  select to_char(at at time zone 'Europe/Vienna', 'YYYY-MM-DD')
      || '-'
      || lpad(
           (((extract(hour from at at time zone 'Europe/Vienna')::int) / 6) * 6)::text,
           2, '0');
$function$;

comment on function public.monitor_slot_key(timestamptz) is
  'Vier Slots je Tag (00/06/12/18 Uhr Wien). Der eindeutige slot_key in '
  'admin_metric_snapshots deckelt damit die schweren Berechnungen auf 4/Tag.';

-- Stuendlich statt zweimal taeglich — siehe Begruendung im Kopf.
select cron.unschedule('admin-metric-snapshot');
select cron.schedule(
  'admin-metric-snapshot',
  '2 * * * *',
  $cron$select public.admin_monitor_take_snapshot();$cron$
);
