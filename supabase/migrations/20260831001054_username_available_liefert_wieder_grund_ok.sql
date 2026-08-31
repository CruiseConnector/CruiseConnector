-- 2026-08-31 — Nutzer zsago888 kam nicht durch die Registrierung.
--
-- Belegt: Am 31.08. zwischen 00:04 und 00:05 UTC rief seine App
-- `username_available` zehnmal auf. Alle zehn Aufrufe antworteten HTTP 200,
-- alle zehn Namen waren FREI. Trotzdem stand in der App zehnmal
-- „Konnte gerade nicht pruefen" und der Weiter-Knopf blieb gesperrt.
--
-- Ursache: Die Migration 20260828190000 (Namenssperre, Kurzschluss und
-- Verfall) hat beim Umbau dieser Funktion den Schluessel `reason` aus dem
-- ERFOLGSFALL verloren. Sie antwortete nur noch {"available": true}.
-- Der Client wertet ausschliesslich `reason` aus:
--
--     case 'ok'            -> Name ist frei
--     case 'taken' ...     -> belegt / reserviert / ungueltig
--     default              -> „Konnte gerade nicht pruefen"
--
-- Ein fehlendes `reason` wird im Client zu 'unknown' und landet damit im
-- default-Zweig. Ergebnis: JEDER freie Name sah aus wie ein Serverfehler.
-- Die drei Absage-Faelle trugen ihren Grund weiter und funktionierten — nur
-- der Erfolg war unzustellbar. Deshalb kam niemand mehr durch den
-- Assistenten, obwohl an Datenbank und Netz nichts fehlte.
--
-- Gemessener Schaden: In den 14 Tagen davor legten 104 Personen ein Konto an,
-- 94 kamen durch das Onboarding. In den Tagen danach: 10 Konten, 0 durch.
--
-- Diese Migration stellt den Vertrag wieder her, den beide Vorgaenger-
-- fassungen (20260627140000 und 20260825100000) und der Client-Kommentar
-- in social_service.dart nennen: reason in {ok, invalid_format, reserved,
-- taken}. Die Pruef-Logik selbst bleibt unveraendert.
--
-- Gegen eine Wiederholung wacht test/auth/username_available_vertrag_test.dart:
-- der Test liest die JEWEILS JUENGSTE Migration, die diese Funktion anfasst,
-- und besteht nur, wenn jeder return-Zweig einen `reason` traegt.

create or replace function public.username_available(p_username text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_uid        uuid := auth.uid();
  v_clean      text := btrim(coalesce(p_username, ''));
  v_schluessel text;
begin
  if not public.is_valid_username_format(v_clean) then
    return jsonb_build_object('available', false, 'reason', 'invalid_format');
  end if;

  v_schluessel := public.benutzername_schluessel(v_clean);

  if exists (
    select 1 from public.reserved_usernames
    where public.benutzername_schluessel(name) = v_schluessel
  ) then
    return jsonb_build_object('available', false, 'reason', 'reserved');
  end if;

  if exists (
    select 1
      from public.profiles p
      join auth.users u on u.id = p.id
     where public.benutzername_schluessel(p.username) = v_schluessel
       and (v_uid is null or p.id <> v_uid)
       and (u.email_confirmed_at is not null
            or u.created_at > now() - interval '48 hours')
  ) then
    return jsonb_build_object('available', false, 'reason', 'taken');
  end if;

  -- Der Erfolgsfall MUSS seinen Grund mitschicken. Ohne ihn liest der Client
  -- 'unknown' und meldet dem Nutzer einen Serverfehler, den es nicht gibt.
  return jsonb_build_object('available', true, 'reason', 'ok');
end;
$function$;

grant execute on function public.username_available(text) to anon, authenticated, service_role;
