-- 2026-08-18 (Defekt 5): Woher kam eine Routenanfrage?
--
-- Der Bericht las 408 von 876 Zeilen ohne `user_id` (47 %) als "die Haelfte
-- der Nutzer ist unbekannt". Nachgemessen stimmt das nicht: an 17 von 21
-- Tagen war KEINE einzige Zeile ohne Konto. Die anonymen Zeilen ballen sich
-- auf vier Tagen und tragen Maschinen-Signatur:
--   16.08. 03:05-03:21 → 399 Zeilen, 25 pro Minute (A/B-Messharness)
--   30.07. 11:03-11:14 →  52 Zeilen, 4,7 pro Minute
--   09.08. 14:20-22:55 →  43 Zeilen, eine einzige Distanz (Server-Arbeit)
--   18.08. 10:22-11:11 →  52 Zeilen (Messungen zu diesem Auftrag)
--
-- Ohne diese Spalte muss man das jedes Mal neu aus Uhrzeiten erraten.
alter table public.route_generation_events
  add column if not exists origin text not null default 'unknown';

alter table public.route_generation_events
  drop constraint if exists route_generation_events_origin_check;
alter table public.route_generation_events
  add constraint route_generation_events_origin_check
  check (origin in ('app', 'test', 'worker', 'unknown'));

create index if not exists route_generation_events_origin_idx
  on public.route_generation_events (origin, created_at desc);

-- Rueckwirkend NUR die beiden Laeufe markieren, die nachweislich Messlaeufe
-- waren. Alles andere bleibt bewusst 'unknown' - lieber ehrlich unbekannt
-- als falsch beschriftet.
update public.route_generation_events
set origin = 'test'
where user_id is null
  and (created_at between '2026-08-16 03:00:00+00' and '2026-08-16 03:30:00+00'
    or created_at between '2026-08-18 10:00:00+00' and '2026-08-18 12:00:00+00');
