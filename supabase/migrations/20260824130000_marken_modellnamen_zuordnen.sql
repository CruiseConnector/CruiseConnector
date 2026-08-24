-- 2026-08-24: Modellnamen im alten Profil-Markenfeld der richtigen Marke
-- zuordnen.
--
-- Vucko hat nachgefragt, was mit "Golf oder Polo koennen in der
-- Markenuebersicht auftauchen" gemeint war. Nachgemessen: profile_vehicles
-- (die Garage) ist nach der Vereinheitlichung sauber, kein einziger
-- Modellname. Die Ausreisser stecken ausschliesslich im ALTEN Feld
-- profiles.car_brand, das frueher frei tippbar war - genau acht von 128:
--   Golf, Polo, Puma, "Audi S3 8P", "VW Golf 7", "Honda CB",
--   "Hyundai Skoda", "Rieju MRT , Ktm Exc"
--
-- Sechs davon sind eindeutig aufloesbar und werden hier zugeordnet. Der
-- Weg dafuer ist vehicle_brand_alias, ausdruecklich "pflegbar ohne
-- App-Deploy" - es braucht also keinen neuen Build.
--
-- ZWEI BLEIBEN ABSICHTLICH STEHEN:
--   "Hyundai Skoda"        - zwei Hersteller in einem Feld
--   "Rieju MRT , Ktm Exc"  - zwei Fahrzeuge in einem Feld
-- Bei beiden waere jede Zuordnung geraten. Wer sein Fahrzeug in die Garage
-- eintraegt, loest das selbst und richtig auf; ich erfinde hier nichts.
--
-- "Puma" ist der Ford Puma. Es gibt keinen Fahrzeughersteller dieses
-- Namens, und der Sportartikel-Hersteller baut keine Autos.

insert into public.vehicle_brand_alias (alias_key, canonical_brand) values
  (public.vehicle_brand_key('Golf'),      'Volkswagen'),
  (public.vehicle_brand_key('Polo'),      'Volkswagen'),
  (public.vehicle_brand_key('VW Golf 7'), 'Volkswagen'),
  (public.vehicle_brand_key('Audi S3 8P'),'Audi'),
  (public.vehicle_brand_key('Honda CB'),  'Honda'),
  (public.vehicle_brand_key('Puma'),      'Ford')
on conflict (alias_key) do update
  set canonical_brand = excluded.canonical_brand;

-- Bestand nachziehen. Der Trigger greift nur beim Schreiben, die schon
-- vorhandenen Zeilen muessen einmal angefasst werden.
update public.profiles
   set car_brand = public.vehicle_brand_canonical(car_brand)
 where car_brand is not null
   and car_brand <> ''
   and car_brand is distinct from public.vehicle_brand_canonical(car_brand);

update public.profile_vehicles
   set brand = public.vehicle_brand_canonical(brand)
 where brand is not null
   and brand <> ''
   and brand is distinct from public.vehicle_brand_canonical(brand);

do $$
declare
  v_rest text;
begin
  select string_agg(car_brand, ' | ' order by car_brand)
    into v_rest
    from (select distinct car_brand from public.profiles
           where car_brand in ('Golf','Polo','Puma','Audi S3 8P',
                               'VW Golf 7','Honda CB')) t;

  if v_rest is not null then
    raise exception 'Diese Modellnamen stehen noch im Profilfeld: %', v_rest;
  end if;

  raise notice 'Modellnamen zugeordnet. Die zwei mehrdeutigen Eintraege bleiben bewusst stehen.';
end $$;
