-- ----------------------------------------------------------------------------
-- 2026-08-24 - Wer benutzt einen Hashtag, und wie viele Leute sind das?
-- ----------------------------------------------------------------------------
--
-- vucko am 24.08.: "Aber da moechte ich das auch noch mit den Hashtags so
-- haben, dass wenn man einen #Bmw, #BayerischeMotorenWerke oder sonstige,
-- dass man sieht, wer alles so einen # benutzt hat. Also wenn ihn schon 17
-- Leute benutzt haben, dann soll das moeglichst da noch drunter stehen [...]
-- man soll drauf klicken koennen wie bei Instagram oder TikTok."
--
-- Warum ueberhaupt etwas Neues?
-- Die Ablage aus Migration 20260824102000 kann heute nur Beitraege zaehlen.
-- `hashtag_vorschlaege.anzahl` ist eine BEITRAGS-Zahl. Wer einen Hashtag
-- vierzig Mal selbst benutzt, erzeugt damit "40" - und die Seite behauptet
-- eine Beliebtheit, die aus einer einzigen Person besteht. Vucko will die
-- PERSONEN sehen, nicht die Beitraege. Das ist eine andere Frage an dieselben
-- Daten und braucht eigene Abfragen.
--
-- ABGRENZUNG, damit hier niemand zu viel hineinliest:
-- #Bmw und #BayerischeMotorenWerke sind ZWEI Hashtags und bleiben zwei.
-- Sie werden NICHT zusammengefasst. Die Marken-Vereinheitlichung aus
-- 20260824101000 (BMW = Bmw = bmw) gilt fuer das Fahrzeug-Markenfeld, NICHT
-- fuer Hashtags. Was `hashtag_schluessel` faltet, bleibt unveraendert:
-- Gross- und Kleinschreibung sowie Umlaut-Schreibweise, also #BMW = #bmw und
-- #Kurvenkoenig = #Kurvenkönig. Mehr nicht - genau so macht es Instagram auch.
--
-- Neu in dieser Migration:
--   1. public.hashtag_personen   - die Personen zu einem Hashtag
--   2. public.hashtag_kennzahlen - Beitraege UND Personen in EINEM Aufruf
--   3. public.hashtag_vorschlaege - bekommt eine Personenzahl dazu
--
-- Nichts davon schreibt. Alles liest aus public.post_hashtags, das weiterhin
-- ausschliesslich vom Trigger post_hashtags_pflegen gefuellt wird.


-- ----------------------------------------------------------------------------
-- 1. Die Personen zu einem Hashtag
-- ----------------------------------------------------------------------------
--
-- SORTIERUNG - bewusste Entscheidung, weil sie das Verhalten der Seite praegt:
-- Sortiert wird nach dem JUENGSTEN Beitrag der Person, nicht nach der
-- Haeufigkeit.
--   * Nach Haeufigkeit waere die Liste eingefroren. Wer einen Hashtag am
--     Eroeffnungstag zwanzig Mal benutzt, steht dort fuer immer oben, und
--     jeder Neuzugang landet unsichtbar auf Platz 30. Das belohnt genau das
--     Verhalten, das wir nicht wollen, und macht die Liste als Anreiz wertlos.
--   * Nach dem juengsten Beitrag lebt die Liste. Wer gerade mit #Bmw postet,
--     sieht sich sofort oben - das ist die Rueckmeldung, die Vucko meint,
--     wenn er von Instagram und TikTok spricht.
-- Zweites Kriterium ist trotzdem die Haeufigkeit (bei gleicher Sekunde),
-- drittes die user_id. Das dritte Kriterium ist kein Schmuck: ohne ein
-- eindeutiges letztes Feld kann dieselbe Person beim Blaettern (p_offset)
-- zweimal oder gar nicht erscheinen.
--
-- FILTER - identisch mit hashtag_beitraege (public, nicht ausgeblendet, nicht
-- gesperrt). Sonst stuende in der Personenliste jemand, dessen Beitrag man
-- gar nicht oeffnen kann.
--
-- ZUSAETZLICH BLOCKIERUNGEN, und nur hier:
-- Die Personenliste ist eine Liste von Gesichtern und Namen. Wer jemanden
-- blockiert hat, soll ihm nicht in einer oeffentlichen Liste begegnen, und
-- umgekehrt genauso - das ist dieselbe Regel, nach der Feed und Entdecken
-- schon heute filtern (blocked_user_ids, is_blocked_pair). Deshalb faellt
-- ein Blockpaar hier heraus.
-- Die ZAHL unter dem Hashtag ist davon bewusst NICHT betroffen, Begruendung
-- steht bei hashtag_kennzahlen.
create or replace function public.hashtag_personen(
  p_tag    text,
  p_limit  int default 50,
  p_offset int default 0
)
returns table (
  user_id    uuid,
  username   text,
  avatar_url text,
  beitraege  bigint,
  zuletzt    timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select
    p.user_id,
    pr.username,
    pr.avatar_url,
    count(*)::bigint      as beitraege,
    max(p.created_at)     as zuletzt
  from public.post_hashtags h
  join public.posts p     on p.id  = h.post_id
  join public.profiles pr on pr.id = p.user_id
  where h.tag_schluessel = public.hashtag_schluessel(
          btrim(regexp_replace(coalesce(p_tag, ''), '^#+', '')))
    and p.visibility = 'public'
    and coalesce(p.is_hidden, false) = false
    and coalesce(pr.is_banned, false) = false
    and not exists (
      select 1
      from public.user_blocks ub
      where (ub.blocker_id = (select auth.uid()) and ub.blocked_id = p.user_id)
         or (ub.blocked_id = (select auth.uid()) and ub.blocker_id = p.user_id)
    )
  group by p.user_id, pr.username, pr.avatar_url
  order by max(p.created_at) desc, count(*) desc, p.user_id
  limit  greatest(1, least(coalesce(p_limit, 50), 200))
  offset greatest(0, coalesce(p_offset, 0));
$fn$;

comment on function public.hashtag_personen(text, int, int) is
  '2026-08-24: Die PERSONEN zu einem Hashtag, nicht die Beitraege. Je Person '
  'wie oft und wann zuletzt. Sortiert nach dem juengsten Beitrag, damit die '
  'Liste nicht von Vielpostern eingefroren wird. Filter wie hashtag_beitraege, '
  'zusaetzlich fallen Blockpaare heraus.';

revoke all on function public.hashtag_personen(text, int, int) from public, anon;
grant execute on function public.hashtag_personen(text, int, int) to authenticated;


-- ----------------------------------------------------------------------------
-- 2. Die Kopfzahlen eines Hashtags - ein Aufruf, nicht zwei
-- ----------------------------------------------------------------------------
--
-- Die Seite braucht beide Zahlen gleichzeitig ("42 Beitraege von 17 Leuten").
-- Zwei getrennte Aufrufe waeren zwei Wartezeiten und koennten sich in der
-- Anzeige widersprechen, wenn zwischendurch jemand postet.
--
-- WARUM DIE ZAHL NICHT NACH BLOCKIERUNGEN GEFILTERT IST:
-- Die Zahl beschreibt den HASHTAG, nicht den Betrachter. Waere sie gefiltert,
-- dann
--   * saehe jeder eine andere Zahl unter demselben Hashtag,
--   * passte sie nicht mehr zur Liste aus hashtag_beitraege (die ebenfalls
--     nicht nach Blockierungen filtert, weil aus ihr Gewinnspiele ausgelost
--     werden und die Auslosung nicht davon abhaengen darf, wer wen blockiert
--     hat),
--   * und man koennte an einer sinkenden Zahl ablesen, dass einen jemand
--     blockiert hat.
-- Deshalb: `personen_anzahl` ist die objektive Zahl - das ist die "17 Leute".
-- Damit die Oberflaeche trotzdem nicht luegen muss, kommt `personen_sichtbar`
-- dazu: so viele Zeilen liefert hashtag_personen diesem Betrachter
-- tatsaechlich. Ohne Blockierungen sind beide Zahlen gleich; das ist der
-- Normalfall (gemessen am 24.08.: 0 Zeilen in user_blocks).
--
-- `tag` ist die Schreibweise, wie sie in post_hashtags steht.
-- ACHTUNG, beim Bauen der Seite gemessen: der Trigger post_hashtags_pflegen
-- speichert `lower(m[1])`, also IMMER klein geschrieben. Aus
-- "#BayerischeMotorenWerke" wird in dieser Spalte "bayerischemotorenwerke".
-- Die Ueberschrift der Seite sollte deshalb den Text nehmen, den der Nutzer
-- angetippt hat, nicht diese Spalte. Die Schreibweise in der Ablage zu
-- erhalten waere eine Aenderung am Schreibweg samt Nachtrag fuer den Bestand -
-- das gehoert nicht in eine Migration, die nur Fragen beantwortet, und
-- braucht Vuckos Entscheidung.
-- Bei einem unbekannten Hashtag kommt genau eine Zeile mit 0/0/0 und tag =
-- null zurueck, nie eine leere Antwort - die Seite muss keinen Sonderfall
-- kennen.
create or replace function public.hashtag_kennzahlen(p_tag text)
returns table (
  tag               text,
  tag_schluessel    text,
  beitraege_anzahl  bigint,
  personen_anzahl   bigint,
  personen_sichtbar bigint
)
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  with schluessel as (
    select public.hashtag_schluessel(
             btrim(regexp_replace(coalesce(p_tag, ''), '^#+', ''))) as k
  ),
  treffer as (
    select
      h.tag,
      p.id         as post_id,
      p.user_id,
      p.created_at,
      not exists (
        select 1
        from public.user_blocks ub
        where (ub.blocker_id = (select auth.uid()) and ub.blocked_id = p.user_id)
           or (ub.blocked_id = (select auth.uid()) and ub.blocker_id = p.user_id)
      ) as sichtbar
    from public.post_hashtags h
    join public.posts p     on p.id  = h.post_id
    join public.profiles pr on pr.id = p.user_id
    cross join schluessel s
    where h.tag_schluessel = s.k
      and p.visibility = 'public'
      and coalesce(p.is_hidden, false) = false
      and coalesce(pr.is_banned, false) = false
  )
  select
    (select t.tag from treffer t order by t.created_at desc, t.post_id limit 1),
    (select k from schluessel),
    count(*)::bigint,
    count(distinct t2.user_id)::bigint,
    count(distinct t2.user_id) filter (where t2.sichtbar)::bigint
  from treffer t2;
$fn$;

comment on function public.hashtag_kennzahlen(text) is
  '2026-08-24: Kopfzahlen eines Hashtags in EINEM Aufruf. beitraege_anzahl '
  'und personen_anzahl sind objektiv (kein Blockfilter, damit jeder dieselbe '
  'Zahl sieht und sie zu hashtag_beitraege passt). personen_sichtbar ist die '
  'Zeilenzahl, die hashtag_personen diesem Betrachter liefert.';

revoke all on function public.hashtag_kennzahlen(text) from public, anon;
grant execute on function public.hashtag_kennzahlen(text) to authenticated;


-- ----------------------------------------------------------------------------
-- 3. hashtag_vorschlaege bekommt die Personenzahl
-- ----------------------------------------------------------------------------
--
-- Aufrufer geprueft, BEVOR die Funktion angefasst wurde:
--   * lib/data/services/social_service.dart -> hashtagVorschlaege() ruft sie
--     mit p_praefix / p_tage / p_limit auf und liest die Antwort in eine Map.
--     Aufgerufen wird sie aus community_page.dart bei jedem Tastendruck in
--     der Suche. Es gibt sonst keinen Aufrufer: keine Edge Function, keine
--     View, keine andere Datenbankfunktion (geprueft ueber pg_depend und
--     eine Volltextsuche im Repo).
-- Deshalb bleiben Name, Parameter und die Spalten tag / tag_schluessel /
-- anzahl UNVERAENDERT. `personen_anzahl` kommt hinten dazu. Eine zusaetzliche
-- Spalte ist fuer den heutigen Client unsichtbar - er liest benannte
-- Schluessel aus einer Map und ignoriert, was er nicht kennt. `anzahl` behaelt
-- absichtlich seine alte Bedeutung (BEITRAEGE); waere die Zahl still auf
-- Personen umgestellt worden, haette die installierte App ploetzlich etwas
-- anderes angezeigt, ohne dass jemand etwas geaendert haette.
--
-- Der Rueckgabetyp aendert sich, deshalb muss die Funktion weg und neu -
-- create or replace kann eine Spalte nicht anhaengen.
--
-- DREI weitere Aenderungen, alle absichtlich:
--
--   a) Gesperrte Verfasser (profiles.is_banned) fallen jetzt heraus. Das war
--      eine echte Unstimmigkeit: hashtag_beitraege filtert sie, die
--      Vorschlagsliste nicht. Ein Hashtag konnte also mit "5 Beitraege"
--      vorgeschlagen werden und beim Antippen drei zeigen.
--
--   b) Sortiert wird zuerst nach Personen, dann nach Beitraegen. Ein Hashtag,
--      den zwoelf Leute je einmal benutzt haben, ist beliebter als einer, den
--      eine Person vierzig Mal getippt hat. Nach Beitraegen zu sortieren
--      hiesse, dass sich jeder die Spitze der Vorschlagsliste allein durch
--      Wiederholung nehmen kann. Genau diese Zahl will Vucko sehen
--      ("wenn ihn schon 17 Leute benutzt haben"), also muss sie auch
--      sortieren.
--
--   c) plpgsql statt sql, und die Abfrage wird zusammengebaut statt fest
--      verdrahtet. Das ist KEINE Stilfrage, sondern gemessen:
--
--        Praefix "gr", 20 000 Beitraege / 22 550 Hashtag-Zeilen
--          alte sql-Fassung ....... 284 ms  (zweimal gemessen, identisch)
--          neue plpgsql-Fassung ....  15 ms
--          dieselbe Abfrage direkt
--          mit festem Muster ......  16 ms
--
--      Grund: in einer sql-Funktion ist das LIKE-Muster ein Parameter. Der
--      Planer kann aus `like $1 || '%'` keine Indexgrenzen ableiten und
--      liest post_hashtags komplett, mit einem Primaerschluessel-Zugriff auf
--      posts je Zeile. Steht das Muster als Literal in der Abfrage, benutzt
--      er post_hashtags_praefix_idx. Diese Funktion laeuft bei JEDEM
--      Tastendruck in der Suche - 284 ms je Buchstabe waeren nicht zu
--      gebrauchen.
--      Das Muster wird ueber format(%L) eingesetzt, also korrekt gequotet.
--      Zusaetzlich werden \ % _ im Suchtext maskiert: bisher konnte ein
--      getipptes "%" als LIKE-Platzhalter durchschlagen und alle Hashtags
--      treffen.
drop function if exists public.hashtag_vorschlaege(text, int, int);

create or replace function public.hashtag_vorschlaege(
  p_praefix text default null,
  p_tage    int  default 30,
  p_limit   int  default 10
)
returns table (
  tag             text,
  tag_schluessel  text,
  anzahl          bigint,
  personen_anzahl bigint
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_roh    text := btrim(regexp_replace(coalesce(p_praefix, ''), '^#+', ''));
  v_muster text;
  v_tage   int  := greatest(1, least(coalesce(p_tage, 30), 365));
  v_limit  int  := greatest(1, least(coalesce(p_limit, 10), 50));
begin
  if v_roh <> '' then
    v_muster := replace(replace(replace(
                  public.hashtag_schluessel(v_roh),
                  '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end if;

  return query execute format($sql$
    select (array_agg(h.tag order by p.created_at desc, p.id))[1],
           h.tag_schluessel,
           count(*)::bigint,
           count(distinct p.user_id)::bigint
      from public.post_hashtags h
      join public.posts p     on p.id  = h.post_id
      join public.profiles pr on pr.id = p.user_id
     where p.visibility = 'public'
       and coalesce(p.is_hidden, false) = false
       and coalesce(pr.is_banned, false) = false
       and p.created_at > now() - (%s * interval '1 day')
       %s
     group by h.tag_schluessel
     order by count(distinct p.user_id) desc, count(*) desc, h.tag_schluessel
     limit %s$sql$,
    v_tage,
    case when v_muster is null then ''
         else format('and h.tag_schluessel like %L', v_muster) end,
    v_limit);
end;
$fn$;

comment on function public.hashtag_vorschlaege(text, int, int) is
  '2026-08-24: Beliebte Hashtags, wahlweise auf einen Praefix eingeschraenkt. '
  'anzahl = Beitraege (unveraendert), personen_anzahl = verschiedene Leute. '
  'Sortiert nach Personen, damit Wiederholung allein niemanden nach oben '
  'bringt. Gesperrte Verfasser zaehlen nicht mehr mit. Das Praefix-Muster '
  'steht als Literal in der Abfrage, sonst bleibt post_hashtags_praefix_idx '
  'ungenutzt (gemessen 284 ms gegen 15 ms).';

revoke all on function public.hashtag_vorschlaege(text, int, int) from public, anon;
grant execute on function public.hashtag_vorschlaege(text, int, int) to authenticated;


-- ----------------------------------------------------------------------------
-- 4. Indizes - gemessen, nicht angenommen
-- ----------------------------------------------------------------------------
--
-- Diese Migration legt KEINEN neuen Index an. Das ist ein Ergebnis, keine
-- Bequemlichkeit. Gemessen am 24.08.2026 in einer Transaktion mit
-- Ruecknahme, 20 000 zusaetzliche Beitraege von 50 Leuten, 22 550 Zeilen in
-- post_hashtags, jeweils zweiter Lauf (warm):
--
--   hashtag_personen    50 Beitraege am Hashtag ......   7 ms
--   hashtag_personen   500 Beitraege am Hashtag ......   8 ms
--   hashtag_personen  2000 Beitraege am Hashtag ......  10 ms
--   hashtag_personen 20000 Beitraege am Hashtag ......  35 ms
--   hashtag_kennzahlen 2000 Beitraege ................  17 ms
--   hashtag_kennzahlen 20000 Beitraege ...............  78 ms
--   hashtag_vorschlaege ohne Praefix .................  58 ms
--   hashtag_vorschlaege mit Praefix ..................  15 ms
--
-- Der Plan fuer die Personenzaehlung nimmt post_hashtags_tag_idx
-- beziehungsweise post_hashtags_praefix_idx fuer den Einstieg und geht dann
-- ueber den Primaerschluessel von posts. Der vorhandene Indexbestand reicht.
-- Ein zusaetzlicher Index auf posts brachte nichts, weil nicht der Einstieg
-- teuer ist, sondern die Zahl der Zeilen, die zusammengezaehlt werden muss.
--
-- AB WANN ES ZAEHLT, ehrlich:
--   * Heute stehen 10 Beitraege und 0 Hashtags in der Datenbank. Jede dieser
--     Abfragen ist unter 1 ms. Die Messung oben ist kuenstlich erzeugt.
--   * Bis etwa 2000 Beitraege AN EINEM EINZELNEN HASHTAG bleibt alles unter
--     20 ms. Das ist die Groessenordnung, die ein Gewinnspiel-Hashtag
--     realistisch erreicht.
--   * Ab etwa 20 000 Beitraegen an einem einzelnen Hashtag wird
--     hashtag_kennzahlen mit 78 ms spuerbar. Dann - und erst dann - ist der
--     richtige Schritt NICHT ein weiterer Index, sondern user_id zusaetzlich
--     in post_hashtags zu fuehren (der Trigger kann sie mitschreiben). Die
--     Personenzahl waere dann eine reine Indexabfrage ohne posts.
--   * hashtag_vorschlaege OHNE Praefix liest immer alle Hashtag-Zeilen des
--     Zeitfensters. Das ist die erste Abfrage, die eine vorberechnete
--     Tagesliste braucht, geschaetzt jenseits von 100 000 Hashtag-Zeilen in
--     30 Tagen. Bis dahin genuegt sie.
