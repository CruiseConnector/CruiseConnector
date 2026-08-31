-- 2026-08-31 — Serverlast: die Startseite laedt 120 volle Geometrien fuer EINE
-- Empfehlung. Siehe den ausfuehrlichen Kommentar im Commit
-- "perf(serverlast): Startseite laedt keine 120 Geometrien mehr".
--
-- Gemessen: 120 Zeilen mit geometry und route_payload = 680 ms und 3040 kB,
-- ohne die beiden Spalten 3 ms und 35 kB. Nicht der Plan ist das Problem,
-- sondern die Nutzlast — ein zusaetzlicher Index waere nutzlos und wurde
-- bewusst NICHT angelegt.
--
-- Der Client zog die Geometrie nur, weil _isSafeHomePoolRoute vier feste
-- Eigenschaften daraus ablas. Die werden hier einmal gemessen und abgelegt.
-- Die SCHWELLEN bleiben im Client: der Server misst, der Client entscheidet.

create or replace function public.route_pool_punkt_anzahl(g jsonb)
returns integer language sql immutable parallel safe
set search_path to 'public', 'pg_temp' as $$
  select coalesce(count(*), 0)::int
  from jsonb_array_elements(case when jsonb_typeof(g->'coordinates') = 'array'
                                 then g->'coordinates' else '[]'::jsonb end) p
  where jsonb_typeof(p) = 'array' and jsonb_array_length(p) >= 2
    and jsonb_typeof(p->0) = 'number' and jsonb_typeof(p->1) = 'number';
$$;

-- Formel und Erdradius stimmen mit GeoDistance.haversineKm im Client ueberein
-- (6371 km, 2*atan2(sqrt(a), sqrt(1-a))). Koordinaten sind [lng, lat].
create or replace function public.route_pool_max_segment_meter(g jsonb)
returns double precision language sql immutable parallel safe
set search_path to 'public', 'pg_temp' as $$
  select coalesce(max(
    6371000 * 2 * atan2(
      sqrt( sin(radians(lat - vlat)/2)^2
            + cos(radians(vlat)) * cos(radians(lat))
              * sin(radians(lng - vlng)/2)^2 ),
      sqrt(1 - ( sin(radians(lat - vlat)/2)^2
            + cos(radians(vlat)) * cos(radians(lat))
              * sin(radians(lng - vlng)/2)^2 ))
    )), 0)::double precision
  from (
    select (p->>0)::float8 as lng, (p->>1)::float8 as lat,
           lag((p->>0)::float8) over (order by o) as vlng,
           lag((p->>1)::float8) over (order by o) as vlat
    from jsonb_array_elements(case when jsonb_typeof(g->'coordinates') = 'array'
                                   then g->'coordinates' else '[]'::jsonb end)
         with ordinality t(p, o)
    where jsonb_typeof(p) = 'array' and jsonb_array_length(p) >= 2
      and jsonb_typeof(p->0) = 'number' and jsonb_typeof(p->1) = 'number'
  ) s where vlat is not null;
$$;

alter table public.route_pool
  add column if not exists punkt_anzahl       integer,
  add column if not exists max_segment_meter  double precision,
  add column if not exists geometrie_quelle   text,
  add column if not exists autobahn_verstoss  boolean;

comment on column public.route_pool.punkt_anzahl is
  'Anzahl gueltiger Koordinatenpunkte. Vom Ausloeser gepflegt, damit Listen '
  'die Geometrie nicht laden muessen.';
comment on column public.route_pool.max_segment_meter is
  'Groesster Sprung zwischen zwei Punkten in Metern. Vom Ausloeser gepflegt.';
comment on column public.route_pool.geometrie_quelle is
  'Herkunft der Geometrie, klein geschrieben, aus route_payload.';
comment on column public.route_pool.autobahn_verstoss is
  'motorway_violation aus route_payload. Vom Ausloeser gepflegt.';

create or replace function public.route_pool_kennzahlen_setzen()
returns trigger language plpgsql
set search_path to 'public', 'pg_temp' as $$
begin
  -- Nur rechnen, wenn sich die Quelle der Zahlen geaendert hat. Sonst kostet
  -- jedes Hochzaehlen von usage_count eine Neuberechnung ueber 1500 Punkte.
  if tg_op = 'INSERT'
     or new.geometry is distinct from old.geometry
     or new.route_payload is distinct from old.route_payload then
    new.punkt_anzahl      := public.route_pool_punkt_anzahl(new.geometry);
    new.max_segment_meter := public.route_pool_max_segment_meter(new.geometry);
    new.geometrie_quelle  := lower(coalesce(
        new.route_payload->>'final_geometry_source',
        new.route_payload->>'geometry_source',
        new.route_payload->>'source', ''));
    -- Fehlender Schluessel heisst "kein Verstoss", wie im Client.
    new.autobahn_verstoss := coalesce(
        (new.route_payload->>'motorway_violation') = 'true', false);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_route_pool_kennzahlen on public.route_pool;
create trigger trg_route_pool_kennzahlen
  before insert or update on public.route_pool
  for each row execute function public.route_pool_kennzahlen_setzen();

update public.route_pool
   set punkt_anzahl      = public.route_pool_punkt_anzahl(geometry),
       max_segment_meter = public.route_pool_max_segment_meter(geometry),
       geometrie_quelle  = lower(coalesce(route_payload->>'final_geometry_source',
                                          route_payload->>'geometry_source',
                                          route_payload->>'source', '')),
       autobahn_verstoss = coalesce((route_payload->>'motorway_violation') = 'true', false)
 where punkt_anzahl is null;
