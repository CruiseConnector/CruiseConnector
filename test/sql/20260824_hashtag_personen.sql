-- ═══════════════════════════════════════════════════════════════════════════
-- Gegenprobe zur Migration
-- 20260824120000_hashtag_personen_und_kennzahlen.sql
--
-- Auftrag Vucko 2026-08-24: „dass man sieht, wer alles so einen # benutzt
-- hat. Also wenn ihn schon 17 Leute benutzt haben, dann soll das moeglichst
-- da noch drunter stehen [...] man soll drauf klicken koennen wie bei
-- Instagram oder TikTok."
--
-- Diese Datei ist KEIN Dart-Test, sondern wird ueber den Supabase-MCP gegen
-- die Datenbank gefahren. Beide Teile laufen komplett in einer Transaktion
-- und enden mit ROLLBACK. Es bleibt NICHTS stehen: nachgerechnet nach dem
-- Lauf am 24.08.2026 wieder 10 Beitraege, 0 Zeilen in post_hashtags,
-- 0 Zeilen in user_blocks, 0 gesperrte Konten.
--
-- Warum Probedaten noetig sind: am 24.08.2026 stehen 10 Beitraege in der
-- Datenbank und KEIN EINZIGER enthaelt eine Raute. Ohne angelegte Hashtags
-- laesst sich keine dieser Abfragen belegen.
--
-- Die eigentliche Gegenprobe sind die Schritte 18 bis 21: dort wird der
-- Zustand VOR der Migration wiederhergestellt (alter Rumpf von
-- hashtag_vorschlaege, beide neuen Abfragen geloescht). Ohne die Aenderung
-- gibt es keine Personenzahl, der Vielposter steht oben, ein getipptes
-- Prozentzeichen trifft alle Hashtags, und die Frage „wer benutzt diesen
-- Hashtag" ist gar nicht beantwortbar.
--
-- ───────────────────────────────────────────────────────────────────────────
-- GEMESSENES ERGEBNIS, Teil 1 (Verhalten), 24.08.2026
-- ───────────────────────────────────────────────────────────────────────────
--   0  Ausgangslage ............ 10 Beitraege, 0 Hashtag-Zeilen, 0 Blockierungen
--   1  Probedaten .............. 19 Beitraege, D gesperrt=true
--   2  kennzahlen(#bmw) ........ tag=bmw, Beitraege=5, Personen=3, sichtbar=3
--   3  #BayerischeMotorenWerke . Beitraege=1, Personen=1  (NICHT mit #Bmw zusammengelegt)
--   4  „BMW" ohne Raute ........ Beitraege=5, Personen=3  (gleiche Zeile wie #bmw)
--   5  #Kurvenkönig/koenig ..... Beitraege=2, Personen=2  (eine Zeile)
--   6  personen(#bmw) .......... cozy (1x) > LucWqz1 (1x) > Vucko (3x)
--   7  gesperrt/ausgeblendet ... Rich=false, JonnyHasb=false  (beide raus)
--   8  Blaettern limit1 offset1  LucWqz1  (genau eine Zeile, keine Dublette)
--   9  unbekannter Hashtag ..... Personen 0 Zeilen, Kennzahlen 1 Zeile mit 0/0
--   10 A blockiert E, A schaut . LucWqz1 > Vucko  (cozy faellt raus)
--   11 Kopfzahl dabei .......... Beitraege=5, Personen=3, davon sichtbar=2
--   12 E schaut ................ cozy > LucWqz1  (Vucko faellt raus, beide Richtungen)
--   13 Unbeteiligter ........... cozy > LucWqz1 > Vucko  (unveraendert)
--   14 vorschlaege NEU ......... bmw 5/3 Leute, echtbeliebt 3/3, kurvenkönig 2/2
--                                (spamtest mit 6 Beitraegen von EINER Person
--                                 faellt aus den ersten drei heraus)
--   15 Praefix „bayer" ......... bayerischemotorenwerke: 1/1
--   16 getipptes „%" ........... LEER  (kein Platzhalter mehr)
--   17 Rechte .................. anon=false/false, authenticated=true/true
--   18 GEGENPROBE alter Rumpf .. spamtest: 6 Beitraege, bmw: 5, echtbeliebt: 3
--                                <-- der Vielposter steht oben
--   19 GEGENPROBE Spalte ....... fehlt: column x.personen_anzahl does not exist
--   20 GEGENPROBE „%" .......... spamtest=6, bmw=5, echtbeliebt=3,
--                                kurvenkönig=2, bayerischemotorenwerke=1
--                                <-- ein getipptes Prozentzeichen traf ALLES
--   21 GEGENPROBE ohne Migration function public.hashtag_personen(unknown,
--                                integer, integer) does not exist
--
-- ───────────────────────────────────────────────────────────────────────────
-- GEMESSENES ERGEBNIS, Teil 2 (Laufzeit), 24.08.2026
-- 20 000 zusaetzliche Beitraege von 50 Leuten, 22 550 Zeilen post_hashtags,
-- jeweils zweiter Lauf (warm), nach ANALYZE
-- ───────────────────────────────────────────────────────────────────────────
--   hashtag_personen      50 Beitraege am Hashtag ......   7,1 ms
--   hashtag_personen     500 Beitraege am Hashtag ......   7,7 ms
--   hashtag_personen    2000 Beitraege am Hashtag ......   9,5 ms
--   hashtag_personen   20000 Beitraege am Hashtag ......  35,5 ms
--   hashtag_kennzahlen  2000 Beitraege ................  17,2 ms
--   hashtag_kennzahlen 20000 Beitraege ................  78,2 ms
--   hashtag_vorschlaege ohne Praefix, sql-Fassung ....  102,1 ms
--   hashtag_vorschlaege mit Praefix,  sql-Fassung ....  283,8 ms
--   hashtag_vorschlaege ohne Praefix, plpgsql ........   57,6 ms
--   hashtag_vorschlaege mit Praefix,  plpgsql ........   14,7 ms
--   dieselbe Abfrage direkt mit festem Muster ........   16,1 ms
--
-- Daraus die Entscheidung in der Migration: KEIN neuer Index (der Einstieg
-- ueber post_hashtags_tag_idx reicht, teuer ist die Zeilenzahl, nicht der
-- Einstieg), aber hashtag_vorschlaege als plpgsql mit eingesetztem Muster -
-- sonst bleibt post_hashtags_praefix_idx bei einem Parameter ungenutzt, und
-- diese Abfrage laeuft bei JEDEM Tastendruck in der Suche.
-- ═══════════════════════════════════════════════════════════════════════════


-- ───────────────────────────────────────────────────────────────────────────
-- TEIL 1: Verhalten und Gegenprobe
-- ───────────────────────────────────────────────────────────────────────────
begin;
create temp table zz(nr int, schritt text, befund text) on commit drop;
do $p$
declare
  a uuid := '1f444750-4407-45cc-8470-1161f866a628';  -- Vucko
  b uuid := 'fc78c265-f7a3-4b5c-a4f5-13711c90072a';  -- LucWqz1
  c uuid := 'dc59b92c-3751-451f-b1ff-5f297286b045';  -- JonnyHasb
  d uuid := 'fb0dc595-7752-4ceb-915a-2f24887ec6dc';  -- Rich, wird gesperrt
  e uuid := '33329d30-59fd-458f-a2be-5f0a9456a00c';  -- cozy
  v text;
begin
  insert into zz values (0, 'Ausgangslage',
    (select count(*) from public.posts) || ' Beitraege, '
    || (select count(*) from public.post_hashtags) || ' Hashtag-Zeilen, '
    || (select count(*) from public.user_blocks) || ' Blockierungen');

  -- Probedaten. Die Hashtags entstehen NICHT von Hand, sondern durch den
  -- Trigger post_hashtags_pflegen - genau wie in der App.
  insert into public.posts (user_id, content, visibility, created_at) values
    (a, 'zz #BMW erster',                     'public',    now() - interval '5 min'),
    (a, 'zz #bmw zweiter',                    'public',    now() - interval '4 min'),
    (a, 'zz #Bmw dritter',                    'public',    now() - interval '3 min'),
    (b, 'zz #bmw und #BayerischeMotorenWerke','public',    now() - interval '2 min'),
    (e, 'zz #bmw von cozy',                   'public',    now() - interval '1 min'),
    (c, 'zz #Bmw nur fuer Follower',          'followers', now()),
    (d, 'zz #bmw von gesperrtem Konto',       'public',    now()),
    (b, 'zz #Kurvenkönig',                    'public',    now()),
    (c, 'zz #kurvenkoenig',                   'public',    now()),
    (a, 'zz #spamtest 1', 'public', now()), (a, 'zz #spamtest 2', 'public', now()),
    (a, 'zz #spamtest 3', 'public', now()), (a, 'zz #spamtest 4', 'public', now()),
    (a, 'zz #spamtest 5', 'public', now()), (a, 'zz #spamtest 6', 'public', now()),
    (b, 'zz #echtbeliebt', 'public', now()),
    (c, 'zz #echtbeliebt', 'public', now()),
    (e, 'zz #echtbeliebt', 'public', now());
  insert into public.posts (user_id, content, visibility, is_hidden, created_at)
    values (c, 'zz #bmw ausgeblendet', 'public', true, now());
  update public.profiles set is_banned = true where id = d;

  insert into zz values (1, 'Probedaten angelegt',
    '19 Beitraege, davon 6 mit bmw-Schluessel; D gesperrt='
    || (select coalesce(is_banned,false) from public.profiles where id=d));

  select 'tag=' || coalesce(k.tag,'NULL') || ', Beitraege=' || k.beitraege_anzahl
      || ', Personen=' || k.personen_anzahl || ', davon sichtbar=' || k.personen_sichtbar
    into v from public.hashtag_kennzahlen('#bmw') k;
  insert into zz values (2, 'hashtag_kennzahlen(#bmw)  ERWARTET 5 Beitraege / 3 Personen', v);

  select 'tag=' || coalesce(k.tag,'NULL') || ', Beitraege=' || k.beitraege_anzahl
      || ', Personen=' || k.personen_anzahl
    into v from public.hashtag_kennzahlen('#BayerischeMotorenWerke') k;
  insert into zz values (3, '#BayerischeMotorenWerke wird NICHT mit #Bmw zusammengelegt', v);

  select 'Beitraege=' || k.beitraege_anzahl || ', Personen=' || k.personen_anzahl
    into v from public.hashtag_kennzahlen('BMW') k;
  insert into zz values (4, 'ohne Raute und in Grossbuchstaben  ERWARTET 5 / 3', v);

  select 'Beitraege=' || k.beitraege_anzahl || ', Personen=' || k.personen_anzahl
    into v from public.hashtag_kennzahlen('#Kurvenkoenig') k;
  insert into zz values (5, 'Kurvenkönig und kurvenkoenig sind ein Hashtag  ERWARTET 2 / 2', v);

  select string_agg(pers.username || ' (' || pers.beitraege || 'x)', ' > ' order by ord)
    into v from (
      select row_number() over () as ord, hp.* from public.hashtag_personen('#bmw', 50, 0) hp
    ) pers;
  insert into zz values (6, 'hashtag_personen(#bmw)  ERWARTET cozy > LucWqz1 > Vucko', v);

  insert into zz values (7, 'gesperrt / ausgeblendet / nur Follower',
    'Rich in der Liste=' || (exists (select 1 from public.hashtag_personen('#bmw',50,0) hp where hp.username='Rich'))
    || ', JonnyHasb in der Liste=' || (exists (select 1 from public.hashtag_personen('#bmw',50,0) hp where hp.username='JonnyHasb')));

  select string_agg(hp.username, ' | ') into v from public.hashtag_personen('#bmw', 1, 1) hp;
  insert into zz values (8, 'Blaettern p_limit=1 p_offset=1  ERWARTET LucWqz1', coalesce(v,'LEER'));

  select 'Zeilen=' || count(*) into v from public.hashtag_personen('#gibtesnicht', 50, 0);
  insert into zz values (9, 'unbekannter Hashtag',
    v || ', Kennzahlen: ' || (select 'tag=' || coalesce(k.tag,'NULL') || ', Beitraege='
      || k.beitraege_anzahl || ', Personen=' || k.personen_anzahl
      from public.hashtag_kennzahlen('#gibtesnicht') k));

  -- Blockierung. Ab hier wird ein angemeldeter Betrachter vorgetaeuscht,
  -- damit auth.uid() in den Abfragen greift.
  insert into public.user_blocks (blocker_id, blocked_id) values (a, e);
  perform set_config('request.jwt.claims', json_build_object('sub', a)::text, true);
  select string_agg(q.username, ' > ' order by ord) into v from (
    select row_number() over () as ord, hp.* from public.hashtag_personen('#bmw',50,0) hp) q;
  insert into zz values (10, 'A hat E blockiert, A schaut  ERWARTET LucWqz1 > Vucko', coalesce(v,'LEER'));

  select 'Beitraege=' || k.beitraege_anzahl || ', Personen=' || k.personen_anzahl
      || ', davon sichtbar=' || k.personen_sichtbar
    into v from public.hashtag_kennzahlen('#bmw') k;
  insert into zz values (11, 'Kopfzahl objektiv, sichtbar sinkt  ERWARTET 5 / 3 / 2', v);

  perform set_config('request.jwt.claims', json_build_object('sub', e)::text, true);
  select string_agg(q.username, ' > ' order by ord) into v from (
    select row_number() over () as ord, hp.* from public.hashtag_personen('#bmw',50,0) hp) q;
  insert into zz values (12, 'E wurde blockiert, E schaut  ERWARTET cozy > LucWqz1', coalesce(v,'LEER'));

  perform set_config('request.jwt.claims', json_build_object('sub', c)::text, true);
  select string_agg(q.username, ' > ' order by ord) into v from (
    select row_number() over () as ord, hp.* from public.hashtag_personen('#bmw',50,0) hp) q;
  insert into zz values (13, 'Unbeteiligter sieht weiter alle drei', coalesce(v,'LEER'));
  perform set_config('request.jwt.claims', '', true);

  select string_agg(x.tag || ': ' || x.anzahl || ' Beitraege / ' || x.personen_anzahl || ' Leute', ', ' order by ord)
    into v from (select row_number() over () as ord, hv.* from public.hashtag_vorschlaege(null, 30, 3) hv) x;
  insert into zz values (14, 'hashtag_vorschlaege NEU  ERWARTET Personen vor Beitraegen', v);

  select string_agg(x.tag || ': ' || x.anzahl || '/' || x.personen_anzahl, ', ')
    into v from public.hashtag_vorschlaege('#bayer', 30, 5) x;
  insert into zz values (15, 'Vorschlaege mit Praefix bayer', coalesce(v,'LEER'));

  select coalesce(string_agg(x.tag, ', '), 'LEER') into v from public.hashtag_vorschlaege('%', 30, 5) x;
  insert into zz values (16, 'getipptes Prozentzeichen ist kein Platzhalter  ERWARTET LEER', v);

  insert into zz values (17, 'Ausfuehrungsrechte',
    'anon/personen=' || has_function_privilege('anon','public.hashtag_personen(text,int,int)','execute')
    || ', anon/kennzahlen=' || has_function_privilege('anon','public.hashtag_kennzahlen(text)','execute')
    || ', authenticated/personen=' || has_function_privilege('authenticated','public.hashtag_personen(text,int,int)','execute')
    || ', authenticated/kennzahlen=' || has_function_privilege('authenticated','public.hashtag_kennzahlen(text)','execute'));

  -- ── GEGENPROBE: Zustand vor der Migration ───────────────────────────────
  drop function public.hashtag_vorschlaege(text, int, int);
  create function public.hashtag_vorschlaege(
    p_praefix text default null, p_tage int default 30, p_limit int default 10)
  returns table (tag text, tag_schluessel text, anzahl bigint)
  language sql stable security definer set search_path = public, pg_temp
  as $alt$
    select (array_agg(h.tag order by p.created_at desc, p.id))[1] as tag,
           h.tag_schluessel, count(*) as anzahl
    from public.post_hashtags h
    join public.posts p on p.id = h.post_id
    where p.visibility = 'public' and coalesce(p.is_hidden, false) = false
      and p.created_at > now() - (greatest(1, least(coalesce(p_tage,30),365)) * interval '1 day')
      and (p_praefix is null or btrim(regexp_replace(p_praefix,'^#+','')) = ''
           or h.tag_schluessel like public.hashtag_schluessel(btrim(regexp_replace(p_praefix,'^#+',''))) || '%')
    group by h.tag_schluessel
    order by count(*) desc, h.tag_schluessel
    limit greatest(1, least(coalesce(p_limit,10),50));
  $alt$;

  select string_agg(x.tag || ': ' || x.anzahl || ' Beitraege', ', ' order by ord)
    into v from (select row_number() over () as ord, hv.* from public.hashtag_vorschlaege(null, 30, 3) hv) x;
  insert into zz values (18, 'GEGENPROBE alter Rumpf: keine Personenzahl, Vielposter oben', v);

  begin
    select count(*)::text into v from public.hashtag_vorschlaege(null,30,3) x where x.personen_anzahl > 0;
    insert into zz values (19, 'GEGENPROBE Spalte personen_anzahl im alten Rumpf', 'unerwartet vorhanden');
  exception when others then
    insert into zz values (19, 'GEGENPROBE Spalte personen_anzahl im alten Rumpf', 'fehlt: ' || SQLERRM);
  end;

  select coalesce(string_agg(x.tag||'='||x.anzahl, ', '), 'LEER') into v
    from public.hashtag_vorschlaege('%', 30, 5) x;
  insert into zz values (20, 'GEGENPROBE alter Rumpf, getipptes Prozentzeichen', v);

  drop function public.hashtag_personen(text,int,int);
  drop function public.hashtag_kennzahlen(text);
  begin
    perform * from public.hashtag_personen('#bmw', 50, 0);
    insert into zz values (21, 'GEGENPROBE ohne Migration', 'unerwartet erfolgreich');
  exception when others then
    insert into zz values (21, 'GEGENPROBE ohne Migration: Personenfrage unbeantwortbar', SQLERRM);
  end;
end $p$;
select nr, schritt, befund from zz order by nr;
rollback;


-- ───────────────────────────────────────────────────────────────────────────
-- TEIL 2: Laufzeit unter Last (ebenfalls mit Ruecknahme)
--
-- 20 000 Beitraege von 50 Leuten. #alle steht an allen, #gross an 2000,
-- #mittel an 500, #klein an 50 - damit laesst sich ablesen, wie die
-- Personenzaehlung mit der Groesse eines Hashtags waechst.
-- ───────────────────────────────────────────────────────────────────────────
begin;
create temp table zzm(nr int, schritt text, befund text) on commit drop;
do $p$
declare ids uuid[]; t0 timestamptz; n int;
begin
  select array_agg(id) into ids from (select id from public.profiles limit 50) q;
  insert into public.posts (user_id, content, visibility, created_at)
  select ids[1 + (g % 50)],
         'zz Last ' || g || ' #alle'
         || case when g <= 2000 then ' #gross'  else '' end
         || case when g <= 500  then ' #mittel' else '' end
         || case when g <= 50   then ' #klein'  else '' end,
         'public', now() - (g || ' minutes')::interval
  from generate_series(1, 20000) g;
  analyze public.posts;
  analyze public.post_hashtags;

  insert into zzm values (1, 'Datenbestand',
    (select count(*) from public.posts) || ' Beitraege, '
    || (select count(*) from public.post_hashtags) || ' Hashtag-Zeilen');

  -- Zwei Laeufe je Abfrage. Der erste enthaelt noch Planungs- und
  -- Lesekosten, gewertet wird der zweite.
  for n in 1..2 loop
    t0 := clock_timestamp();
    perform * from public.hashtag_personen('#klein', 50, 0);
    insert into zzm values (10+n, 'hashtag_personen #klein (50), Lauf '||n,
      round(extract(epoch from clock_timestamp()-t0)*1000, 1) || ' ms');

    t0 := clock_timestamp();
    perform * from public.hashtag_personen('#mittel', 50, 0);
    insert into zzm values (20+n, 'hashtag_personen #mittel (500), Lauf '||n,
      round(extract(epoch from clock_timestamp()-t0)*1000, 1) || ' ms');

    t0 := clock_timestamp();
    perform * from public.hashtag_personen('#gross', 50, 0);
    insert into zzm values (30+n, 'hashtag_personen #gross (2000), Lauf '||n,
      round(extract(epoch from clock_timestamp()-t0)*1000, 1) || ' ms');

    t0 := clock_timestamp();
    perform * from public.hashtag_personen('#alle', 50, 0);
    insert into zzm values (40+n, 'hashtag_personen #alle (20000), Lauf '||n,
      round(extract(epoch from clock_timestamp()-t0)*1000, 1) || ' ms');

    t0 := clock_timestamp();
    perform * from public.hashtag_kennzahlen('#gross');
    insert into zzm values (50+n, 'hashtag_kennzahlen #gross (2000), Lauf '||n,
      round(extract(epoch from clock_timestamp()-t0)*1000, 1) || ' ms');

    t0 := clock_timestamp();
    perform * from public.hashtag_kennzahlen('#alle');
    insert into zzm values (60+n, 'hashtag_kennzahlen #alle (20000), Lauf '||n,
      round(extract(epoch from clock_timestamp()-t0)*1000, 1) || ' ms');

    t0 := clock_timestamp();
    perform * from public.hashtag_vorschlaege(null, 30, 10);
    insert into zzm values (70+n, 'hashtag_vorschlaege ohne Praefix, Lauf '||n,
      round(extract(epoch from clock_timestamp()-t0)*1000, 1) || ' ms');

    t0 := clock_timestamp();
    perform * from public.hashtag_vorschlaege('gr', 30, 10);
    insert into zzm values (80+n, 'hashtag_vorschlaege Praefix gr, Lauf '||n,
      round(extract(epoch from clock_timestamp()-t0)*1000, 1) || ' ms');
  end loop;
end $p$;

-- Der Plan zur Personenzaehlung. Erwartet: Einstieg ueber einen der beiden
-- Indizes auf post_hashtags, danach Primaerschluessel auf posts.
explain (analyze, buffers, costs off, timing off)
select * from public.hashtag_personen('#gross', 50, 0);

select nr, schritt, befund from zzm order by nr;
rollback;
