-- 2026-08-24, Aufgabe 2.1: Fahrzeug-Marken vereinheitlichen.
--
-- Vucko woertlich: "B-M-W ganz in Caps geschrieben und gross geschrieben soll
-- das Gleiche sein wie B gross, M klein und W klein [...] Wichtig ist, dass
-- das [wortident] ist, nicht ob es jetzt gross oder klein geschrieben ist."
--
-- Gemessener Stand vor dieser Migration:
--   profile_vehicles: 77 Zeilen mit Marke, 36 verschiedene Schreibweisen.
--     bmw/Bmw/BMW = 22 Fahrzeuge, audi/AUDI = 10, Volkswagen/VOLKSWAGEN = 4,
--     skoda/Skoda = 3, ktm/KTM = 2, seat/Seat, Vw = 3.
--   profiles.car_brand: 128 Zeilen mit Marke, 48 verschiedene Schreibweisen.
--     Zusaetzlich WORTVERSCHIEDEN und deshalb durch Kleinschreibung allein
--     nicht loesbar: Vw gegen Volkswagen, Mercedes (6) gegen Mercedes Benz (1),
--     Derby (1) gegen Derbi (2).
--   Das Admin-Monitoring (RPC admin_monitor_metrics, Block "garage")
--     gruppiert ebenfalls roh und zeigt heute "BMW 14" und "Bmw 7"
--     untereinander.
--
-- Warum Tabelle UND Funktion, nicht nur eines von beidem:
--   * Die Funktion allein kann "Vw" nicht zu "Volkswagen" machen und
--     "Derby" nicht zu "Derbi". Das ist Wissen, kein Algorithmus.
--   * Die Tabelle allein reicht nicht, weil jeder Aufrufer sonst selbst
--     entscheiden muesste, wie er den Nachschlage-Schluessel bildet
--     (Kleinschreibung? Bindestriche? Akzente?). Genau daran laufen Client
--     und Dashboard auseinander.
--   Also: vehicle_brand_key() bildet den Schluessel (Mechanik, immutable),
--   vehicle_brand_alias haelt die Zuordnung (Wissen, pflegbar ohne Deploy),
--   vehicle_brand_canonical() ist der EINE Aufruf fuer alle.
--
-- Die kanonischen Schreibweisen sind NICHT geraten. Sie stammen aus der
-- gepflegten Liste in lib/data/services/vehicle_api_service.dart:29-72
-- ("BMW" gross, "Volkswagen" nicht, "McLaren" mit grossem L,
-- "Mercedes-Benz" mit Bindestrich). Ein Algorithmus errraet das falsch:
-- FahrzeugGrenzen.normalisiereMarke() macht heute aus "GasGas" ein "Gasgas"
-- und aus "McLaren" ein "Mclaren".

-- ---------------------------------------------------------------------------
-- 1. Der Gruppierungsschluessel
-- ---------------------------------------------------------------------------

-- Rein textliche Normalisierung: Kleinschreibung, Akzente auf ASCII,
-- alles ausser Buchstaben und Ziffern faellt weg. Damit sind "BMW", "bmw",
-- " Bmw " derselbe Schluessel, ebenso "Mercedes-Benz" und "Mercedes Benz",
-- ebenso "Skoda" und "Škoda". Immutable, damit die Funktion in Ausdruecken
-- und notfalls in Indizes benutzbar bleibt.
create or replace function public.vehicle_brand_key(p_raw text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select nullif(
    regexp_replace(
      translate(
        replace(lower(btrim(coalesce(p_raw, ''))), 'ß', 'ss'),
        'áàâãäåāăçćčďéèêëēěğíìîïīľĺñńňóòôõöøōřśšşťúùûüūůýÿźżž',
        'aaaaaaaacccdeeeeeegiiiiillnnnooooooorssstuuuuuuyyzzz'
      ),
      '[^a-z0-9]', '', 'g'
    ),
    ''
  );
$$;

comment on function public.vehicle_brand_key(text) is
  'Gruppierungsschluessel einer Markenschreibweise. Nur Mechanik: '
  'Kleinschreibung, Akzente auf ASCII, Sonderzeichen weg. Das Wissen ueber '
  'wortverschiedene Namen (Vw/Volkswagen) steht in vehicle_brand_alias.';

-- ---------------------------------------------------------------------------
-- 2. Die kanonische Anzeige-Schreibweise
-- ---------------------------------------------------------------------------

create table if not exists public.vehicle_brand_alias (
  alias_key       text primary key,
  canonical_brand text not null,
  created_at      timestamptz not null default now()
);

comment on table public.vehicle_brand_alias is
  '2026-08-24: Zuordnung Schreibweise -> kanonische Marke. alias_key ist '
  'immer das Ergebnis von vehicle_brand_key(). Faengt auch die '
  'wortverschiedenen Faelle: Vw->Volkswagen, Mercedes->Mercedes-Benz, '
  'Derby->Derbi. Pflegbar ohne App-Deploy.';

alter table public.vehicle_brand_alias enable row level security;

drop policy if exists vehicle_brand_alias_read on public.vehicle_brand_alias;
create policy vehicle_brand_alias_read
  on public.vehicle_brand_alias
  for select
  to authenticated
  using (true);

revoke all on public.vehicle_brand_alias from public, anon;
grant select on public.vehicle_brand_alias to authenticated;

-- Die Liste. Erste Spalte = kanonische Schreibweise (Wahrheit:
-- vehicle_api_service.dart), zweite Spalte = eine Schreibweise, die darauf
-- zeigen soll. Gross-/Kleinschreibung, Bindestriche und Leerzeichen muessen
-- hier NICHT variiert werden, das erledigt vehicle_brand_key().
-- Erfunden wird nichts: alle 36 in der Datenbank vorkommenden Schreibweisen
-- sind abgedeckt, dazu die gaengigen Hersteller aus dem DACH-Raum.
-- distinct on faengt Schreibweisen ab, die denselben Schluessel ergeben
-- (Citroen/Citroën, Skoda/Škoda), sonst bricht ON CONFLICT ab.
insert into public.vehicle_brand_alias (alias_key, canonical_brand)
select distinct on (public.vehicle_brand_key(v.alias))
       public.vehicle_brand_key(v.alias), v.kanonisch
from (values
  -- Autos, kanonische Schreibweise aus vehicle_api_service.dart
  ('Abarth','Abarth'),
  ('Alfa Romeo','Alfa Romeo'), ('Alfa Romeo','Alfa'),
  ('Aston Martin','Aston Martin'), ('Aston Martin','Aston'),
  ('Audi','Audi'),
  ('Bentley','Bentley'),
  ('BMW','BMW'),
  ('Bugatti','Bugatti'),
  ('Chevrolet','Chevrolet'), ('Chevrolet','Chevy'),
  ('Citroen','Citroen'),
  ('Cupra','Cupra'),
  ('Dacia','Dacia'),
  ('Dodge','Dodge'),
  ('Ferrari','Ferrari'),
  ('Fiat','Fiat'),
  ('Ford','Ford'),
  ('Honda','Honda'),
  ('Hyundai','Hyundai'),
  ('Jaguar','Jaguar'),
  ('Jeep','Jeep'),
  ('Kia','Kia'),
  ('Lamborghini','Lamborghini'), ('Lamborghini','Lambo'),
  ('Land Rover','Land Rover'), ('Land Rover','Range Rover'),
  ('Lexus','Lexus'),
  ('Maserati','Maserati'),
  ('Mazda','Mazda'),
  ('McLaren','McLaren'),
  ('Mercedes-Benz','Mercedes-Benz'), ('Mercedes-Benz','Mercedes'),
  ('Mercedes-Benz','Benz'), ('Mercedes-Benz','MB'),
  ('Mini','Mini'),
  ('Mitsubishi','Mitsubishi'),
  ('Nissan','Nissan'),
  ('Opel','Opel'),
  ('Peugeot','Peugeot'),
  ('Porsche','Porsche'),
  ('Renault','Renault'),
  ('Seat','Seat'),
  ('Skoda','Skoda'),
  ('Subaru','Subaru'),
  ('Suzuki','Suzuki'),
  ('Tesla','Tesla'),
  ('Toyota','Toyota'),
  ('Volkswagen','Volkswagen'), ('Volkswagen','VW'),
  ('Volvo','Volvo'),
  -- Weitere gaengige Autos
  ('Smart','Smart'),
  ('Alpine','Alpine'),
  ('Polestar','Polestar'),
  ('Genesis','Genesis'),
  ('MG','MG'),
  ('DS','DS'), ('DS','DS Automobiles'),
  ('Lada','Lada'),
  ('Saab','Saab'),
  ('Rover','Rover'),
  ('Lancia','Lancia'),
  ('Chrysler','Chrysler'),
  ('Cadillac','Cadillac'),
  ('GMC','GMC'),
  ('RAM','RAM'),
  ('Lincoln','Lincoln'),
  ('Buick','Buick'),
  ('Acura','Acura'),
  ('Infiniti','Infiniti'),
  ('Isuzu','Isuzu'),
  ('SsangYong','SsangYong'),
  ('Daihatsu','Daihatsu'),
  ('BYD','BYD'),
  ('NIO','NIO'),
  ('Xpeng','Xpeng'),
  -- Motorraeder und Kleinkraftraeder
  ('Aprilia','Aprilia'),
  ('Benelli','Benelli'),
  ('Beta','Beta'),
  ('Cagiva','Cagiva'),
  ('CFMoto','CFMoto'),
  ('Derbi','Derbi'), ('Derbi','Derby'),
  ('Ducati','Ducati'),
  ('Fantic','Fantic'),
  ('GasGas','GasGas'),
  ('Harley-Davidson','Harley-Davidson'), ('Harley-Davidson','Harley'),
  ('Husaberg','Husaberg'),
  ('Husqvarna','Husqvarna'),
  ('Indian','Indian'),
  ('Kawasaki','Kawasaki'),
  ('Keeway','Keeway'),
  ('Kreidler','Kreidler'),
  ('KTM','KTM'),
  ('Kymco','Kymco'),
  ('Malaguti','Malaguti'),
  ('Moto Guzzi','Moto Guzzi'), ('Moto Guzzi','Guzzi'),
  ('MV Agusta','MV Agusta'),
  ('Piaggio','Piaggio'),
  ('Puch','Puch'),
  ('Puma','Puma'),
  ('Rieju','Rieju'),
  ('Royal Enfield','Royal Enfield'),
  ('Sherco','Sherco'),
  ('Simson','Simson'),
  ('SWM','SWM'),
  ('SYM','SYM'),
  ('Triumph','Triumph'),
  ('TM Racing','TM Racing'),
  ('Vespa','Vespa'),
  ('Voge','Voge'),
  ('Yamaha','Yamaha'),
  ('Zero','Zero'),
  ('Zontes','Zontes'),
  ('Zündapp','Zündapp'), ('Zündapp','Zuendapp')
) as v(kanonisch, alias)
order by public.vehicle_brand_key(v.alias), v.kanonisch
on conflict (alias_key) do update set canonical_brand = excluded.canonical_brand;

-- Nachschlagen mit Rueckfallebene. WICHTIG: ist eine Schreibweise unbekannt,
-- wird NICHT geraten. Dann bleibt der getippte Text stehen (nur Leerzeichen
-- werden aufgeraeumt). Genau daran scheitert der heutige Client-Algorithmus,
-- der aus "GasGas" ein "Gasgas" macht.
-- Bewusst SECURITY INVOKER: authenticated hat ueber die Policy
-- vehicle_brand_alias_read Leserecht auf die Zuordnungstabelle, und
-- admin_monitor_metrics ist selbst Definer und umgeht RLS ohnehin. Eine
-- Definer-Funktion wuerde der Supabase-Advisor sonst zu Recht melden
-- (Regel authenticated_security_definer_function_executable).
create or replace function public.vehicle_brand_canonical(p_raw text)
returns text
language sql
stable
set search_path = public, pg_temp
as $$
  select coalesce(
    (select a.canonical_brand
       from public.vehicle_brand_alias a
      where a.alias_key = public.vehicle_brand_key(p_raw)),
    nullif(regexp_replace(btrim(coalesce(p_raw, '')), '\s+', ' ', 'g'), '')
  );
$$;

comment on function public.vehicle_brand_canonical(text) is
  '2026-08-24: DIE eine Stelle, die aus einer getippten Marke die kanonische '
  'Schreibweise macht. Unbekannte Marken bleiben unveraendert stehen, es '
  'wird nichts geraten.';

revoke all on function public.vehicle_brand_key(text) from public, anon;
revoke all on function public.vehicle_brand_canonical(text) from public, anon;
grant execute on function public.vehicle_brand_key(text) to authenticated, service_role;
grant execute on function public.vehicle_brand_canonical(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Bestandsdaten mitziehen, in BEIDEN Tabellen
-- ---------------------------------------------------------------------------

update public.profile_vehicles
   set brand = public.vehicle_brand_canonical(brand)
 where brand is not null
   and btrim(brand) <> ''
   and brand is distinct from public.vehicle_brand_canonical(brand);

update public.profiles
   set car_brand = public.vehicle_brand_canonical(car_brand)
 where car_brand is not null
   and btrim(car_brand) <> ''
   and car_brand is distinct from public.vehicle_brand_canonical(car_brand);

-- ---------------------------------------------------------------------------
-- 4. Damit kuenftig nichts Neues entsteht: Trigger beim Schreiben
-- ---------------------------------------------------------------------------
--
-- Entscheidung: JA, mit Einschraenkung.
-- Dafuer: 183 Profile, alte App-Versionen bleiben installiert und schreiben
--   weiter "Bmw". Dieselbe Falle wie bei der Laender-Klassifikation, wo der
--   Client-Wert deshalb serverseitig ueberschrieben wird. Kein Client kann
--   am Trigger vorbei, auch kein kuenftiger Import.
-- Dagegen (der Nachteil aus dem Auftrag): der Nutzer sieht etwas anderes,
--   als er getippt hat.
-- Aufloesung: der Trigger schreibt NUR um, wenn die Schreibweise in
--   vehicle_brand_alias steht. Dann ist die Ersetzung wortident und genau
--   das, was Vucko verlangt ("bmw" ist dasselbe wie "BMW"). Unbekannte
--   Eingaben bleiben Zeichen fuer Zeichen stehen, es wird nur der
--   Leerraum aufgeraeumt. Damit kann der Trigger nie eine Marke
--   verunstalten, die er nicht kennt.

create or replace function public.tg_vehicle_brand_normalize()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.brand is not null then
    new.brand := public.vehicle_brand_canonical(new.brand);
  end if;
  return new;
end;
$$;

create or replace function public.tg_profile_car_brand_normalize()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.car_brand is not null then
    new.car_brand := public.vehicle_brand_canonical(new.car_brand);
  end if;
  return new;
end;
$$;

revoke all on function public.tg_vehicle_brand_normalize() from public, anon;
revoke all on function public.tg_profile_car_brand_normalize() from public, anon;

drop trigger if exists trg_vehicle_brand_normalize on public.profile_vehicles;
create trigger trg_vehicle_brand_normalize
  before insert or update of brand on public.profile_vehicles
  for each row execute function public.tg_vehicle_brand_normalize();

drop trigger if exists trg_profile_car_brand_normalize on public.profiles;
create trigger trg_profile_car_brand_normalize
  before insert or update of car_brand on public.profiles
  for each row execute function public.tg_profile_car_brand_normalize();

-- ---------------------------------------------------------------------------
-- 5. Admin-Monitoring mitziehen
-- ---------------------------------------------------------------------------
--
-- admin_monitor_metrics gruppiert im Block "garage" roh nach brand und zeigt
-- deshalb "BMW 14" und "Bmw 7" untereinander. Die Bestandsdaten oben
-- reparieren das heute, der Funktionsaufruf haelt es dauerhaft: Dashboard
-- und App gruppieren ab jetzt nach derselben Regel.
-- Der Rest der Funktion bleibt Zeichen fuer Zeichen unveraendert; die
-- Migration bricht ab, falls der Block nicht mehr so aussieht wie erwartet.
-- Ein zweiter Lauf ist harmlos: ist der Block schon umgestellt, passiert nichts.
do $patch$
declare
  d_alt text;
  d_neu text;
  such  text := 'select brand k, count(*) c from profile_vehicles';
  ersatz text := 'select public.vehicle_brand_canonical(brand) k, count(*) c from profile_vehicles';
begin
  select pg_get_functiondef(p.oid) into d_alt
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_monitor_metrics';

  if d_alt is null then
    raise exception 'admin_monitor_metrics nicht gefunden, Migration abgebrochen';
  end if;

  -- Schon umgestellt (z. B. weil die Migration erneut laeuft): nichts tun.
  if position(ersatz in d_alt) > 0 then
    raise notice 'Garage-Block ist bereits umgestellt, nichts zu tun';
  elsif position(such in d_alt) = 0 then
    raise exception 'Garage-Block in admin_monitor_metrics sieht anders aus als erwartet, Migration abgebrochen';
  else
    d_neu := replace(d_alt, such, ersatz);
    execute d_neu;
  end if;
end
$patch$;

-- ---------------------------------------------------------------------------
-- 6. Fundament fuer Aufgabe 2.2: Marken-Uebersicht und Drilldown
-- ---------------------------------------------------------------------------
--
-- Warum RPC und nicht direkt lesen, obwohl profile_vehicles_public_read
-- "using true" ist:
--   * Der Client muesste die Gruppierung selbst bauen, und genau dieses
--     Doppelt-Bauen ist die Ursache des Problems, das wir hier reparieren.
--   * Die Uebersicht braucht beide Quellen (Garage und Profil). Diese
--     Entscheidung gehoert an EINE Stelle, nicht in jede Ansicht.
--   * Der Drilldown braucht profiles (Name, Bild). Ueber die Tabelle waere
--     das ein Join pro Marke.
-- Beide Funktionen laufen bewusst als SECURITY INVOKER: so greift RLS,
-- Profile von Personen, die sich gegenseitig blockiert haben, fallen von
-- selbst weg, und Uebersicht und Drilldown zeigen dieselbe Zahl.
--
-- Quellen-Entscheidung (128 Profile mit Marke gegen 60 Personen mit
-- Garagen-Zeile):
--   * profile_vehicles ist fuehrend. Nur dort steht vehicle_type, ohne den
--     der Filter Auto/Motorrad gar nicht moeglich ist, und nur dort ist die
--     Marke ein eigenes Feld.
--   * profiles.car_brand ist Freitext und enthaelt Modelle statt Marken
--     ("Audi S3 8P", "VW Golf 7", "Golf", "Polo"). Es zaehlt deshalb NUR
--     als Rueckfallebene, und nur fuer Personen ohne jede Garagen-Zeile,
--     damit niemand doppelt gezaehlt wird. Sichtbar ist diese Ebene nur im
--     Filter "Alle", weil ihr die Fahrzeugart fehlt.

create or replace function public.get_brand_overview(p_vehicle_type text default 'all')
returns table (
  brand        text,
  people       integer,
  vehicles     integer,
  from_garage  integer,
  from_profile integer
)
language sql
stable
set search_path = public, pg_temp
as $$
  with art as (
    select case
             when lower(coalesce(p_vehicle_type, 'all')) in ('car', 'motorcycle')
               then lower(p_vehicle_type)
             else 'all'
           end as wert
  ),
  garage as (
    select v.user_id,
           public.vehicle_brand_canonical(v.brand) as brand
      from public.profile_vehicles v
      join public.profiles p on p.id = v.user_id
     cross join art
     where v.brand is not null
       and btrim(v.brand) <> ''
       and p.is_banned is not true
       and (art.wert = 'all' or v.vehicle_type = art.wert)
  ),
  nur_profil as (
    select p.id as user_id,
           public.vehicle_brand_canonical(p.car_brand) as brand
      from public.profiles p
     cross join art
     where art.wert = 'all'
       and p.car_brand is not null
       and btrim(p.car_brand) <> ''
       and p.is_banned is not true
       and not exists (
             select 1 from public.profile_vehicles v
              where v.user_id = p.id
                and v.brand is not null
                and btrim(v.brand) <> ''
           )
  ),
  alle as (
    select user_id, brand, 'garage'::text as quelle from garage
    union all
    select user_id, brand, 'profil'::text as quelle from nur_profil
  )
  select a.brand,
         count(distinct a.user_id)::int,
         count(*)::int,
         count(*) filter (where a.quelle = 'garage')::int,
         count(*) filter (where a.quelle = 'profil')::int
    from alle a
   where a.brand is not null
   group by a.brand
   order by count(distinct a.user_id) desc, a.brand asc;
$$;

comment on function public.get_brand_overview(text) is
  '2026-08-24 (Aufgabe 2.2): Marken-Uebersicht. p_vehicle_type: car, '
  'motorcycle oder all. Fuehrend ist profile_vehicles; profiles.car_brand '
  'zaehlt nur fuer Personen ohne Garagen-Zeile und nur bei all.';

create or replace function public.get_brand_members(
  p_brand        text,
  p_vehicle_type text default 'all'
)
returns table (
  user_id      uuid,
  username     text,
  avatar_url   text,
  brand        text,
  model        text,
  vehicle_type text,
  source       text
)
language sql
stable
set search_path = public, pg_temp
as $$
  with art as (
    select case
             when lower(coalesce(p_vehicle_type, 'all')) in ('car', 'motorcycle')
               then lower(p_vehicle_type)
             else 'all'
           end as wert
  ),
  gesucht as (select public.vehicle_brand_canonical(p_brand) as marke)
  select p.id,
         p.username,
         p.avatar_url,
         public.vehicle_brand_canonical(v.brand),
         v.model,
         v.vehicle_type,
         'garage'::text
    from public.profile_vehicles v
    join public.profiles p on p.id = v.user_id
   cross join art
   cross join gesucht
   where p.is_banned is not true
     and v.brand is not null
     and btrim(v.brand) <> ''
     and public.vehicle_brand_canonical(v.brand) = gesucht.marke
     and (art.wert = 'all' or v.vehicle_type = art.wert)
  union all
  select p.id,
         p.username,
         p.avatar_url,
         public.vehicle_brand_canonical(p.car_brand),
         null::text,
         null::text,
         'profil'::text
    from public.profiles p
   cross join art
   cross join gesucht
   where art.wert = 'all'
     and p.car_brand is not null
     and btrim(p.car_brand) <> ''
     and p.is_banned is not true
     and public.vehicle_brand_canonical(p.car_brand) = gesucht.marke
     and not exists (
           select 1 from public.profile_vehicles v
            where v.user_id = p.id
              and v.brand is not null
              and btrim(v.brand) <> ''
         );
$$;

comment on function public.get_brand_members(text, text) is
  '2026-08-24 (Aufgabe 2.2): Personen zu einer Marke. Dieselben Quellen und '
  'dieselbe Filterung wie get_brand_overview, damit die Zahlen zusammenpassen.';

revoke all on function public.get_brand_overview(text) from public, anon;
revoke all on function public.get_brand_members(text, text) from public, anon;
grant execute on function public.get_brand_overview(text) to authenticated;
grant execute on function public.get_brand_members(text, text) to authenticated;
