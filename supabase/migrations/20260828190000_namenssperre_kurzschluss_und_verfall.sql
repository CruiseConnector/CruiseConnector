-- ---------------------------------------------------------------------------
-- 2026-08-28, Fehler 3 der Meldungen (Instagram-Nutzer Justin):
-- "Hab ein Konto erstellt und hab es nicht fertig gemacht und jetzt kann ich
--  mich nicht registrieren oder anmelden."
--
-- GEMESSEN AN DER PRODUKTION:
--
-- 1. Justins Konto (Apple-Anmeldung, Mail damit automatisch bestaetigt) hat
--    @Justin am 09.08. ERFOLGREICH gesetzt und dann das Onboarding vor dem
--    Abschluss abgebrochen. Seitdem: jeder Login fuehrt in die Namensmaske,
--    "Justin" gilt als frei (der eigene Name ist von der Eindeutigkeit
--    ausgenommen), aber "Weiter" ruft set_username, und dort schlaegt die
--    30-Tage-Sperre zu, BEVOR irgendjemand fragt, ob sich der Name ueberhaupt
--    aendert. Er besitzt den Namen und kommt trotzdem nicht daran vorbei.
--    13 Konten stecken in exakt dieser Falle (6 Apple, 4 E-Mail, 1 Google).
--
-- 2. Dazu der Wunsch des Betreibers: "Der Nutzername ist erst richtig
--    verifiziert, wenn die E-Mail auch bestaetigt wurde." Heute reserviert
--    schon das UNBESTAETIGTE Konto den Namen fuer immer — drei solcher
--    Karteileichen halten gerade echte Namen fest.
--
-- ZWEI AENDERUNGEN, beide in denselben zwei Funktionen:
--
-- A) GLEICHHEITS-KURZSCHLUSS: Ist der gewuenschte Name (gefaltet) der EIGENE
--    aktuelle Name, ist das keine Aenderung. set_username antwortet ok, ohne
--    username_changed_at anzufassen. Damit heilen alle 13 haengenden Konten
--    von selbst: anmelden, Weiter druecken, fertig.
--
-- B) VERFALL UNBESTAETIGTER RESERVIERUNGEN: Ein Name, den nur ein Konto
--    haelt, dessen E-Mail nach 48 Stunden immer noch unbestaetigt ist, gilt
--    als frei. set_username raeumt die Karteileiche in dem Moment ab, in dem
--    jemand den Namen wirklich nimmt (der Guard-Trigger wird dafuer sauber
--    durchlassen). 48 Stunden sind bewusst grosszuegig: wer sich echt
--    registriert, bestaetigt in Minuten.
-- ---------------------------------------------------------------------------

create or replace function public.username_available(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
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

  -- Belegt ist ein Name nur, wenn ihn ein LEBENDIGES fremdes Konto haelt:
  -- entweder mit bestaetigter Mail, oder juenger als 48 Stunden (Frist zum
  -- Bestaetigen). Karteileichen zaehlen nicht mehr.
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

  return jsonb_build_object('available', true);
end;
$fn$;

create or replace function public.set_username(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_uid        uuid := auth.uid();
  v_clean      text := btrim(coalesce(p_username, ''));
  v_schluessel text;
  v_eigener    text;
  v_last       timestamptz;
  v_next       timestamptz;
  v_days       int;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  if not public.is_valid_username_format(v_clean) then
    return jsonb_build_object('ok', false, 'error', 'invalid_format');
  end if;

  v_schluessel := public.benutzername_schluessel(v_clean);

  if exists (
    select 1 from public.reserved_usernames
    where public.benutzername_schluessel(name) = v_schluessel
  ) then
    return jsonb_build_object('ok', false, 'error', 'reserved');
  end if;

  -- (A) KEIN Wechsel, keine Sperre: der eigene Name darf jederzeit bestaetigt
  -- werden. Genau daran hingen Justin und zwoelf weitere — Onboarding
  -- abgebrochen, beim Wiedereinstieg denselben Namen getippt, und die Sperre
  -- griff vor der Gleichheitspruefung. Die Schreibweise darf sich dabei
  -- mitschleifen (justin -> Justin), der Schluessel bleibt ja derselbe.
  select username, username_changed_at
    into v_eigener, v_last
    from public.profiles where id = v_uid;
  if v_eigener is not null
     and public.benutzername_schluessel(v_eigener) = v_schluessel then
    if v_eigener is distinct from v_clean then
      perform set_config('app.username_change_ok', '1', true);
      update public.profiles set username = v_clean where id = v_uid;
      perform set_config('app.username_change_ok', '', true);
    end if;
    return jsonb_build_object('ok', true, 'username', v_clean,
      'unchanged', true,
      'next_change_at', coalesce(v_last, now()) + interval '30 days');
  end if;

  -- 30-Tage-Sperre (Server-Zeit; null => Erstvergabe ist frei)
  if v_last is not null then
    v_next := v_last + interval '30 days';
    if now() < v_next then
      v_days := greatest(0, ceil(extract(epoch from (v_next - now())) / 86400.0))::int;
      return jsonb_build_object('ok', false, 'error', 'too_soon',
        'next_change_at', v_next, 'days_remaining', v_days);
    end if;
  end if;

  -- Eindeutigkeit ueber die Faltung; lebendige fremde Inhaber blocken,
  -- Karteileichen (unbestaetigt, aelter als 48 h) nicht.
  if exists (
    select 1
      from public.profiles p
      join auth.users u on u.id = p.id
     where public.benutzername_schluessel(p.username) = v_schluessel
       and p.id <> v_uid
       and (u.email_confirmed_at is not null
            or u.created_at > now() - interval '48 hours')
  ) then
    return jsonb_build_object('ok', false, 'error', 'taken');
  end if;

  -- (B) Karteileiche abraeumen, falls sie den Namen noch haelt. Das Konto
  -- selbst bleibt bestehen (vielleicht bestaetigt der Mensch ja doch noch);
  -- es verliert nur die Reservierung und waehlt beim echten Einstieg neu.
  perform set_config('app.username_change_ok', '1', true);
  update public.profiles p
     set username = null
    from auth.users u
   where u.id = p.id
     and public.benutzername_schluessel(p.username) = v_schluessel
     and p.id <> v_uid
     and u.email_confirmed_at is null
     and u.created_at <= now() - interval '48 hours';

  update public.profiles
     set username = v_clean, username_changed_at = now()
   where id = v_uid;
  perform set_config('app.username_change_ok', '', true);

  return jsonb_build_object('ok', true, 'username', v_clean,
    'next_change_at', now() + interval '30 days', 'days_remaining', 30);
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'error', 'taken');
  when check_violation then
    return jsonb_build_object('ok', false, 'error', 'invalid_format');
end;
$fn$;

comment on function public.set_username(text) is
  '2026-08-28: Eigener Name ist jederzeit bestaetigbar (Gleichheits-'
  'Kurzschluss vor der 30-Tage-Sperre), unbestaetigte Reservierungen '
  'verfallen nach 48 Stunden. Vorher: Umlaut-Faltung vom 25.08.';
