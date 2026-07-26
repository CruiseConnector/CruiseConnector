-- Stau-Ausdehnung nachtragen. Vorher lief das ueber ein direktes UPDATE mit
-- spalten-beschraenktem Recht; da der Client jetzt gar nicht mehr schreibt,
-- braucht es dafuer eine Funktion. Zusaetzlich eine Plausibilitaetsgrenze:
-- ein Stau ist nicht 50 km lang, und ohne Deckel koennte man ueber das
-- Endpunkt-Feld eine Linie quer durchs Land zeichnen.
create or replace function public.update_jam_extent(
  p_incident_id uuid,
  p_end_lat double precision,
  p_end_lng double precision
) returns void
language plpgsql security definer
set search_path to 'public'
as $$
declare inc road_incidents%rowtype;
begin
  if auth.uid() is null then raise exception 'nicht angemeldet' using errcode = '28000'; end if;
  select * into inc from road_incidents where id = p_incident_id;
  if not found then raise exception 'Meldung unbekannt' using errcode = '02000'; end if;
  if inc.reported_by <> auth.uid() then
    raise exception 'nicht deine Meldung' using errcode = '42501';
  end if;
  if inc.type <> 'stau' then
    raise exception 'nur bei Stau' using errcode = '22023';
  end if;
  if geo_distance_m(inc.lat, inc.lng, p_end_lat, p_end_lng) > 30000 then
    raise exception 'Stau-Laenge unplausibel' using errcode = '22023';
  end if;
  update road_incidents
     set jam_end_lat = p_end_lat, jam_end_lng = p_end_lng
   where id = p_incident_id;
end;
$$;
revoke execute on function public.update_jam_extent(uuid, double precision, double precision) from public, anon;
grant execute on function public.update_jam_extent(uuid, double precision, double precision) to authenticated;;
