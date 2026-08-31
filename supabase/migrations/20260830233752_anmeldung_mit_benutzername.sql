-- ============================================================================
-- Anmelden mit dem @-Namen statt mit der E-Mail-Adresse.
--
-- Vucko am 31.08.2026: "dass man sich entweder wenn man sich halt direkt
-- anmeldet oder halt ein Konto mit seine E-Mail-Adresse hat oder allgemein
-- mit Google, dass man sich auch mit seinen Benutzernamen nur mit seinem
-- Passwort anmelden kann."
--
-- DAS PROBLEM. Supabase-Auth kennt nur die E-Mail. Wer sich mit "@vucko"
-- anmelden will, braucht also irgendwo eine Aufloesung Name -> E-Mail. Genau
-- da liegt die Falle: eine Funktion, die zu einem Namen die E-Mail liefert,
-- macht aus jeder oeffentlichen Namensliste eine Adressliste. Die Namen sind
-- oeffentlich (Profile, Rangliste, Community), die Adressen sind es nicht.
-- Eine solche Funktion waere ein Datenleck, kein Komfort.
--
-- DIE ENTSCHEIDUNG. Die E-Mail verlaesst den Server nie. Diese Funktion gibt
-- nur die BENUTZER-ID zurueck, und auch die nur an `service_role` - also
-- ausschliesslich an die Edge Function `username-login`, die damit
-- serverseitig die Adresse nachschlaegt und die Anmeldung gleich selbst
-- durchfuehrt. Der Client bekommt am Ende ein Sitzungs-Token, sonst nichts.
-- Die Benutzer-ID selbst ist ohnehin kein Geheimnis: sie steht in jedem
-- Profil, jedem Beitrag und jeder Ranglistenzeile.
--
-- WARUM UEBERHAUPT EINE DATENBANKFUNKTION UND KEINE ABFRAGE IN DER EDGE?
-- Wegen der Faltung. Seit dem 25.08. duerfen Namen Umlaute tragen, und
-- "Müller" ist derselbe Name wie "mueller"
-- (public.benutzername_schluessel). Wer diese Faltung in TypeScript
-- nachbaut, hat sie ab dem Tag doppelt und irgendwann verschieden. Hier
-- steht sie einmal - und die Bedingung trifft zeichengleich den vorhandenen
-- Index `ux_profiles_username_schluessel`, die Suche ist also ein
-- Index-Treffer und kein Tabellendurchlauf.
-- ============================================================================

create or replace function public.anmeldename_zu_benutzer_id(p_name text)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select p.id
  from public.profiles p
  where p.username is not null
    and btrim(p.username) <> ''
    and public.benutzername_schluessel(p.username)
        = public.benutzername_schluessel(btrim(p_name))
  limit 1;
$fn$;

comment on function public.anmeldename_zu_benutzer_id(text) is
  '2026-08-31: Loest einen @-Namen auf die Benutzer-ID auf, damit sich '
  'jemand mit Namen und Passwort anmelden kann. Gibt NIEMALS die E-Mail '
  'zurueck. Ausfuehrbar nur fuer service_role, also nur fuer die Edge '
  'Function username-login. Faltet ueber benutzername_schluessel, trifft '
  'damit den Index ux_profiles_username_schluessel.';

-- Ausdruecklich fuer NIEMANDEN ausser service_role. Ohne dieses revoke haette
-- jeder angemeldete Client die Funktion aufrufen koennen - harmlos, weil sie
-- nur eine ohnehin oeffentliche ID liefert, aber es gibt keinen Grund dafuer,
-- und ein spaeterer Umbau auf mehr Rueckgabefelder waere dann sofort ein Leck.
revoke all on function public.anmeldename_zu_benutzer_id(text)
  from public, anon, authenticated;
grant execute on function public.anmeldename_zu_benutzer_id(text)
  to service_role;
