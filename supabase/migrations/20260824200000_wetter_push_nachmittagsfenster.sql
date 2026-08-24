-- 2026-08-24, Vucko: "ich moechte das die taeglichen benachrichtigungen fuer
-- eine strecke erst am nachmittag kommen sollen zwischen 13 - 20 uhr und immer
-- unterschiedlich sein sollen".
--
-- GEMESSEN vor dieser Migration, an 20 Tagen in `notifications`:
-- jede Wetter-Meldung lag zwischen 08:00:03 und 08:01:29 Wiener Zeit. Am
-- 24.08. waren das 183 Zeilen in 53 Sekunden. Ursache: cron-Job
-- 'daily_weather_push' mit '0 6 * * *' — und weil pg_cron in UTC laeuft,
-- waren das im Sommer 08:00 und im Winter 07:00 Wiener Zeit.
--
-- Diese Migration macht drei Dinge:
--   1. Sie schliesst die Idempotenz-Luecke (UNIQUE-Index, den es nie gab).
--   2. Sie stellt den Job auf ein Fenster um, das ganzjaehrig stimmt.
--   3. Sie ersetzt den alten Job, statt einen zweiten danebenzustellen.


-- ---------------------------------------------------------------------------
-- 1. Idempotenz: pro Nutzer und WIENER Tag genau eine Wetter-Meldung.
--
-- Im Quelltext der Edge Function stand seit Mai der Kommentar
-- "Idempotenz: pro user_id + Datum nur EINE Weather-Notification (UNIQUE)".
-- Der Index dazu existierte nie. Abgesichert war nur ein SELECT vor dem
-- INSERT — und das ist ein Lesen-dann-Schreiben ohne Sperre: zwei
-- gleichzeitige Laeufe sehen beide "noch nichts da" und schreiben beide.
--
-- Der Bestand beweist es: vier Nutzer-Tage mit mehr als einer Zeile, darunter
-- der 24.06. mit DREI Meldungen an denselben Nutzer (08:00, 18:30, 18:43) und
-- der 24.05., an dem ein Lauf um 01:03 Wiener Zeit in UTC noch im Vortag lag
-- und der 08:01-Lauf ihn deshalb nicht gefunden hat.
--
-- Erst aufraeumen, sonst laesst sich der Index nicht anlegen.
with rang as (
  select id,
         row_number() over (
           partition by user_id, (timezone('Europe/Vienna', created_at))::date
           order by created_at
         ) as nr
    from public.notifications
   where type = 'weather_recommendation'
)
delete from public.notifications n
 using rang
 where n.id = rang.id and rang.nr > 1;

-- timezone(text, timestamptz) ist IMMUTABLE (geprueft in pg_proc: provolatile
-- = 'i'), darf also in einem Index-Ausdruck stehen. Der Umweg ueber
-- created_at::date waere falsch, weil der von der TimeZone-Einstellung der
-- Sitzung abhaengt — und die ist hier UTC.
create unique index if not exists uniq_wetter_meldung_pro_wiener_tag
  on public.notifications (
    user_id,
    ((timezone('Europe/Vienna', created_at))::date)
  )
  where type = 'weather_recommendation';

comment on index public.uniq_wetter_meldung_pro_wiener_tag is
  'Eine Wetter-Meldung je Nutzer und Wiener Kalendertag. Die Vorpruefung in '
  'der Edge Function ist nur der schnelle Weg; dieser Index ist die Wahrheit '
  'und faengt auch zwei gleichzeitig laufende Jobs ab.';


-- ---------------------------------------------------------------------------
-- 2. Die Schranke in WIENER Zeit.
--
-- Die Falle: pg_cron rechnet in UTC (current_setting('TimeZone') = 'UTC').
-- Ein fester UTC-Zeitpunkt wandert zweimal im Jahr um eine Stunde. '0 15 * * *'
-- waere im Sommer 17:00 und im Winter 16:00 — beides zwar im Fenster, aber
-- jedes Fenster-Ende und jeder Fenster-Anfang liegt dann irgendwann daneben.
-- Und cron.timezone laesst sich auf Supabase nicht je Job setzen.
--
-- Deshalb: der Job tickt in UTC bewusst BREITER als das Fenster, und ob
-- wirklich gesendet wird, entscheidet Postgres in 'Europe/Vienna'. Postgres
-- kennt die Zeitzonendatenbank, also stimmt das auch nach jeder kuenftigen
-- Umstellungsregel — ohne dass jemand zweimal im Jahr an einen cron-Ausdruck
-- denken muss.
create or replace function public.wetter_push_ausloesen()
returns void
language plpgsql
security definer
set search_path = public, net, vault, pg_temp
as $$
declare
  jetzt_wien time := (now() at time zone 'Europe/Vienna')::time;
  basis      text;
begin
  -- Vuckos Vorgabe: ab 13:00, vor 20:00 Wiener Zeit.
  if jetzt_wien < time '13:00' or jetzt_wien >= time '20:00' then
    return;
  end if;

  select decrypted_secret into basis
    from vault.decrypted_secrets
   where name = 'route_pool_healing_project_url'
   limit 1;
  if basis is null then
    -- Laut scheitern statt still nichts tun: ein stummer Wetter-Push faellt
    -- niemandem auf, ein Eintrag in cron.job_run_details schon.
    raise exception 'wetter_push_ausloesen: Projekt-URL fehlt im Vault';
  end if;

  perform net.http_post(
    url     := basis || '/functions/v1/daily-weather-push',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body    := jsonb_build_object('trigger', 'pg_cron')
  );
end;
$$;

revoke execute on function public.wetter_push_ausloesen()
  from public, anon, authenticated;

comment on function public.wetter_push_ausloesen() is
  'Torwaechter fuer den Wetter-Push. Prueft das Versandfenster in Wiener Zeit '
  'und ruft dann erst die Edge Function. Haelt die Sommerzeit aus dem '
  'cron-Ausdruck heraus.';


-- ---------------------------------------------------------------------------
-- 3. Den Job ERSETZEN, nicht danebenstellen.
--
-- cron.schedule aktualisiert einen gleichnamigen Job zwar, aber der alte
-- Job hiess genauso und trug den Aufruf frueher direkt im Kommando. Damit
-- diese Migration auch bei einem spaeteren Umbenennen nie zwei Jobs
-- hinterlaesst, wird vorher jeder Job mit einem der bekannten Namen entfernt.
do $$
declare
  ids bigint[];
  einer bigint;
begin
  select coalesce(array_agg(jobid), '{}') into ids
    from cron.job
   where jobname in ('daily_weather_push', 'daily-weather-push');
  foreach einer in array ids loop
    perform cron.unschedule(einer);
  end loop;
end
$$;

-- '*/5 11-19 * * *' UTC deckt beide Zeitrechnungen ab:
--   Sommer (UTC+2): 13:00-21:55 Wiener Zeit
--   Winter (UTC+1): 12:00-20:55 Wiener Zeit
-- In beiden Faellen liegt 13:00-19:55 vollstaendig drin; alles ausserhalb
-- verwirft die Schranke oben, ohne einen HTTP-Aufruf zu machen.
-- Der 5-Minuten-Takt ist die Rasterweite der Streuung: die Edge Function gibt
-- jedem Nutzer aus user_id + Datum einen eigenen Slot im Fenster, damit die
-- Meldung nicht jeden Tag zur selben Minute und nicht bei allen gleichzeitig
-- ankommt.
select cron.schedule(
  'daily_weather_push',
  '*/5 11-19 * * *',
  $$select public.wetter_push_ausloesen();$$
);
