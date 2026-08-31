-- 2026-08-31 — Was der Reiter "Webseite" im Monitoring anzeigt.
--
-- Der Kern ist der Abgleich "hat die Person die App schon?". Er laeuft ueber
-- die Adresse: die Webseite fragt ausdruecklich nach der Google-Konto-Adresse
-- fuer den Play-Store-Test, und mit derselben meldet sich die Person spaeter
-- in der App an. Gross- und Kleinschreibung sowie Leerzeichen werden dabei
-- vereinheitlicht.
--
-- Gemessen beim Einbau: 72 Anmeldungen, davon 13 mit Konto in der App und 59
-- ohne. Das sind die 59, die auf eine Antwort warten.

create or replace function public.admin_monitor_webseite()
returns jsonb language sql stable security definer
set search_path to 'public', 'pg_temp' as $$
  with angereichert as (
    select w.*, u.id as app_konto, u.created_at as app_seit,
           u.last_sign_in_at as app_zuletzt, p.username as app_name,
           p.onboarding_completed as app_fertig
    from public.web_anmeldungen w
    left join auth.users u on lower(btrim(u.email)) = lower(btrim(w.email))
    left join public.profiles p on p.id = u.id
  )
  select jsonb_build_object(
    'stand', (select jsonb_build_object(
        'letzter_lauf', letzter_lauf, 'letzter_erfolg', letzter_erfolg,
        'letzter_fehler', letzter_fehler, 'meldungen_aktiv', meldungen_aktiv)
      from public.web_abgleich_stand where id = 1),
    'zahlen', (select jsonb_build_object(
        'gesamt',             count(*),
        'bestaetigt',         count(*) filter (where bestaetigt),
        'offen_bestaetigung', count(*) filter (where not bestaetigt),
        'hat_app',            count(*) filter (where app_konto is not null),
        'ohne_app',           count(*) filter (where app_konto is null),
        'ohne_app_offen',     count(*) filter (where app_konto is null and erledigt_am is null),
        'erledigt',           count(*) filter (where erledigt_am is not null),
        'letzte_7_tage',      count(*) filter (where angemeldet_am > now() - interval '7 days'),
        'letzte_24h',         count(*) filter (where angemeldet_am > now() - interval '24 hours'))
      from angereichert),
    'liste', coalesce((select jsonb_agg(jsonb_build_object(
               'id', id, 'name', btrim(vorname || ' ' || nachname),
               'email', email, 'angemeldet_am', angemeldet_am,
               'bestaetigt', bestaetigt, 'hat_app', app_konto is not null,
               'app_name', app_name, 'app_fertig', coalesce(app_fertig, false),
               'app_zuletzt', app_zuletzt, 'erledigt_am', erledigt_am, 'notiz', notiz)
             -- Wer wartet, steht oben: zuerst die Offenen ohne App, darin die
             -- aeltesten zuerst. Die warten am laengsten.
             order by (erledigt_am is not null), (app_konto is not null), angemeldet_am)
      from angereichert), '[]'::jsonb));
$$;

create or replace function public.admin_monitor_webseite_erledigt(
  p_id bigint, p_erledigt boolean default true, p_notiz text default null)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp' as $$
begin
  update public.web_anmeldungen
     set erledigt_am  = case when p_erledigt then now() else null end,
         erledigt_von = case when p_erledigt then auth.uid() else null end,
         notiz        = coalesce(p_notiz, notiz)
   where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'fehler', 'unbekannt'); end if;
  return jsonb_build_object('ok', true);
end;
$$;

-- Wie die uebrigen Monitoring-Funktionen: nur die Service-Rolle. Der
-- Dashboard-Zugang laeuft ueber die Edge Function mit eigener Anmeldung.
revoke all on function public.admin_monitor_webseite() from public, anon, authenticated;
revoke all on function public.admin_monitor_webseite_erledigt(bigint, boolean, text) from public, anon, authenticated;
grant execute on function public.admin_monitor_webseite() to service_role;
grant execute on function public.admin_monitor_webseite_erledigt(bigint, boolean, text) to service_role;
