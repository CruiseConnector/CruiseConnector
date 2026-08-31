-- 2026-08-31 — Auftrag 13 (Vucko, ausdruecklich als LETZTES):
-- "dass ich die Benachrichtigung bekomme, dass sich jemand ueber die Webseite
--  fuer den Android-Test angemeldet hat [...] Mach einen Tab der Webseite
--  heisst im Monitoring-Tool."
--
-- AUSGANGSLAGE, selbst ermittelt:
--   * Das Formular liegt auf cruiseconnector.at/home/anmeldung und sendet an
--     /api/register des eigenen Webservers (~/Development/CruiseConnectorWebsite).
--   * Dieser schreibt in ein ZWEITES Supabase-Projekt (Website_Cruise_Connector,
--     lamijxnyakbxgutssisi), Tabelle `signups`. Nicht in dieses hier.
--   * Stand heute: 72 Anmeldungen, 56 bestaetigt, seit dem 26.03.
--   * Ueber Pruefsummen der Adressen abgeglichen: nur 13 dieser 72 haben ein
--     Konto in der App. 59 haben sich gemeldet und sind nie aufgetaucht.

create table if not exists public.web_anmeldungen (
  -- Die Kennung aus signups. Damit ist der Abgleich wiederholbar: derselbe
  -- Datensatz landet nie zweimal, egal wie oft abgeholt wird.
  id                bigint primary key,
  vorname           text        not null,
  nachname          text        not null,
  email             text        not null,
  angemeldet_am     timestamptz not null,
  bestaetigt        boolean     not null default false,
  -- Wann diese Zeile bei uns eintraf. Nicht dasselbe wie angemeldet_am: beim
  -- ersten Abgleich kommen 72 Altzeilen auf einmal herein.
  eingetroffen_am   timestamptz not null default now(),
  -- Verhindert, dass der Nachtrag der Altbestaende 72 Push-Meldungen ausloest.
  gemeldet_am       timestamptz,
  -- Vuckos Nachhol-Liste: 59 Leute warten auf eine Antwort.
  erledigt_am       timestamptz,
  erledigt_von      uuid references auth.users(id) on delete set null,
  notiz             text
);

comment on table public.web_anmeldungen is
  'Spiegel der signups aus dem Website-Projekt, plus Bearbeitungsstand.';

create index if not exists idx_web_anmeldungen_offen
  on public.web_anmeldungen (angemeldet_am desc) where erledigt_am is null;

-- Niemand ausser der Service-Rolle kommt direkt heran. Das Monitoring liest
-- ueber SECURITY-DEFINER-Funktionen, genau wie bei den uebrigen Kennzahlen.
-- Der Advisor meldet das als rls_enabled_no_policy; das ist hier die Absicht.
alter table public.web_anmeldungen enable row level security;

create or replace function public.web_anmeldungen_uebernehmen(p_zeilen jsonb)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp' as $$
declare
  v_neu int := 0; v_aktualisiert int := 0;
  v_zeile jsonb; v_war_neu boolean;
begin
  if p_zeilen is null or jsonb_typeof(p_zeilen) <> 'array' then
    return jsonb_build_object('ok', false, 'fehler', 'keine_liste');
  end if;
  for v_zeile in select * from jsonb_array_elements(p_zeilen) loop
    -- Eine kaputte Zeile darf die anderen 71 nicht mitreissen.
    continue when v_zeile->>'id' is null or v_zeile->>'email' is null;
    insert into public.web_anmeldungen
      (id, vorname, nachname, email, angemeldet_am, bestaetigt)
    values ((v_zeile->>'id')::bigint,
            coalesce(v_zeile->>'firstname', ''),
            coalesce(v_zeile->>'lastname', ''),
            v_zeile->>'email',
            coalesce((v_zeile->>'created_at')::timestamptz, now()),
            coalesce((v_zeile->>'verified')::boolean, false))
    on conflict (id) do update
      set bestaetigt = excluded.bestaetigt, vorname = excluded.vorname,
          nachname = excluded.nachname, email = excluded.email
    returning (xmax = 0) into v_war_neu;
    if v_war_neu then v_neu := v_neu + 1; else v_aktualisiert := v_aktualisiert + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'neu', v_neu, 'aktualisiert', v_aktualisiert);
end;
$$;

revoke all on function public.web_anmeldungen_uebernehmen(jsonb) from public, anon, authenticated;
grant execute on function public.web_anmeldungen_uebernehmen(jsonb) to service_role;
