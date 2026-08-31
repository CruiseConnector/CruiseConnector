-- 2026-08-31 — Die Bruecke zum Website-Projekt.
--
-- Warum diese Richtung: Das Website-Projekt hat kein pg_net und kann nicht von
-- sich aus funken. Dieses hier hat es und benutzt es schon fuer den
-- Infra-Check und die Pool-Pflege. Also holt die App ab.
--
-- Ein einziger Auftrag genuegt, weil er beides tut: Er sammelt zuerst die
-- Antwort der VORIGEN Runde ein und stellt dann die naechste Anfrage. pg_net
-- arbeitet asynchron; ein Aufruf, der auf seine eigene Antwort warten wollte,
-- wuerde ewig warten.
--
-- Die Zugangsdaten stehen im Vault, nicht im Code. Der anon-Schluessel des
-- Website-Projekts ist KEIN Geheimnis (er steht im Quelltext der Webseite);
-- die Schranke ist das Abholgeheimnis. Es laesst sich jederzeit drehen: hier
-- neu setzen und im Website-Projekt unter 'monitoring_abholgeheimnis'
-- denselben Wert hinterlegen.
--
-- Die Werte werden bewusst NICHT in dieser Datei gefuehrt. Sie stehen im
-- Vault der Produktionsdatenbank; ein leerer Vault fuehrt zu einem sauberen
-- Fehler in web_abgleich_stand.letzter_fehler, nicht zu stillem Nichtstun.

create table if not exists public.web_abgleich_stand (
  id                  int primary key default 1 check (id = 1),
  letzte_anfrage_id   bigint,
  letzter_lauf        timestamptz,
  letzter_erfolg      timestamptz,
  letzter_fehler      text,
  -- Solange false, werden uebernommene Zeilen NICHT gemeldet. Das ist der
  -- Schalter fuer den Nachtrag der Altbestaende: 72 Zeilen sollen keine 72
  -- Push-Meldungen ausloesen.
  meldungen_aktiv     boolean not null default false
);
insert into public.web_abgleich_stand (id) values (1) on conflict do nothing;
alter table public.web_abgleich_stand enable row level security;

-- Meldet neue Anmeldungen an die Monitoring-Admins. Der Weg ist derselbe, den
-- admin-monitor fuer seine Alarme benutzt: eine Zeile in notifications, den
-- Rest erledigt trg_notify_push_on_notification.
create or replace function public.web_anmeldungen_melden()
returns int language plpgsql security definer
set search_path to 'public', 'pg_temp' as $$
declare
  v_aktiv boolean; v_zeile record; v_gemeldet int := 0;
begin
  select meldungen_aktiv into v_aktiv from public.web_abgleich_stand where id = 1;
  if not coalesce(v_aktiv, false) then
    -- Nachtrag laeuft: als gemeldet abhaken, ohne zu melden.
    update public.web_anmeldungen set gemeldet_am = now() where gemeldet_am is null;
    return 0;
  end if;
  for v_zeile in
    select * from public.web_anmeldungen where gemeldet_am is null order by angemeldet_am
  loop
    insert into public.notifications (user_id, from_user_id, type, payload)
    select a.user_id, a.user_id, 'webseite_anmeldung',
           jsonb_build_object(
             'title', 'Neue Anmeldung über die Webseite',
             'body',  v_zeile.vorname || ' ' || v_zeile.nachname
                      || ' möchte die App auf Android testen. ' || v_zeile.email,
             'anmeldung_id', v_zeile.id, 'email', v_zeile.email)
    from public.monitor_admins a where a.aktiv and a.user_id is not null;
    update public.web_anmeldungen set gemeldet_am = now() where id = v_zeile.id;
    v_gemeldet := v_gemeldet + 1;
  end loop;
  return v_gemeldet;
end;
$$;
revoke all on function public.web_anmeldungen_melden() from public, anon, authenticated;

create or replace function public.web_anmeldungen_abgleichen()
returns jsonb language plpgsql security definer
set search_path to 'public', 'vault', 'net', 'pg_temp' as $$
declare
  v_alte_anfrage bigint; v_status int; v_inhalt jsonb; v_uebernommen jsonb;
  v_gemeldet int := 0; v_url text; v_key text; v_geheimnis text;
  v_neue_anfrage bigint;
begin
  select letzte_anfrage_id into v_alte_anfrage from public.web_abgleich_stand where id = 1;

  -- 1) Antwort der vorigen Runde einsammeln.
  if v_alte_anfrage is not null then
    select status_code, case when content is null then null else content::jsonb end
      into v_status, v_inhalt from net._http_response where id = v_alte_anfrage;
    if v_status = 200 and v_inhalt ? 'zeilen' then
      v_uebernommen := public.web_anmeldungen_uebernehmen(v_inhalt->'zeilen');
      v_gemeldet := public.web_anmeldungen_melden();
      update public.web_abgleich_stand set letzter_erfolg = now(), letzter_fehler = null where id = 1;
    elsif v_status is not null then
      update public.web_abgleich_stand set letzter_fehler = 'HTTP ' || v_status where id = 1;
    end if;
    -- Kein Eintrag heisst: laeuft noch oder vom Aufraeum-Auftrag entfernt.
    -- Beides ist kein Fehler; die naechste Runde fragt ohnehin neu.
  end if;

  -- 2) Neue Anfrage stellen.
  select decrypted_secret into v_url       from vault.decrypted_secrets where name='webseite_projekt_url' limit 1;
  select decrypted_secret into v_key       from vault.decrypted_secrets where name='webseite_anon_key' limit 1;
  select decrypted_secret into v_geheimnis from vault.decrypted_secrets where name='webseite_abholgeheimnis' limit 1;
  if v_url is null or v_key is null or v_geheimnis is null then
    update public.web_abgleich_stand
       set letzter_fehler = 'Zugangsdaten fehlen im Vault', letzter_lauf = now() where id = 1;
    return jsonb_build_object('ok', false, 'fehler', 'zugangsdaten_fehlen');
  end if;

  select net.http_post(
    url := v_url || '/rest/v1/rpc/web_anmeldungen_abholen',
    headers := jsonb_build_object('Content-Type','application/json',
                                  'apikey', v_key, 'Authorization', 'Bearer ' || v_key),
    -- Bewusst ohne p_seit: 72 Zeilen sind nichts, und ein vollstaendiger
    -- Abgleich holt auch nachtraegliche Bestaetigungen mit.
    body := jsonb_build_object('p_geheimnis', v_geheimnis),
    timeout_milliseconds := 8000
  ) into v_neue_anfrage;

  update public.web_abgleich_stand
     set letzte_anfrage_id = v_neue_anfrage, letzter_lauf = now() where id = 1;
  return jsonb_build_object('ok', true, 'uebernommen', v_uebernommen,
                            'gemeldet', v_gemeldet, 'anfrage', v_neue_anfrage);
end;
$$;
revoke all on function public.web_anmeldungen_abgleichen() from public, anon, authenticated;

-- Alle fuenf Minuten. Der Auftrag sammelt zuerst die Antwort der vorigen Runde
-- ein und stellt dann die naechste — die Meldung kommt also spaetestens zehn
-- Minuten nach der Anmeldung.
select cron.schedule('webseite-anmeldungen-abgleich', '*/5 * * * *',
                     $cron$select public.web_anmeldungen_abgleichen();$cron$);
