-- ============================================================================
-- 2026-08-24  Community-Chat: Verlauf (wer kam, wer ging), Bearbeiten mit
--             Frist, Loeschen fuer alle oder nur fuer mich, Chat-Art
-- ============================================================================
--
-- Vucko woertlich am 24.08.:
--   "man soll sehen wer dazu gekommen ist und wer aus der community gegangen
--    ist danach"
--   "man soll seine Nachrichten bis zu 6h nach abschicken bearbeiten koennen
--    danach gehts nicht mehr"
--   "auch fuer alle loeschen koennen oder nur fuer sich selber wie bei
--    whatsapp"
--   "man soll die chat art optimieren koennen wie bspw. ob man den standart
--    chat oder einen Nachrichten Chat bevorzugt"
--   "und nicht durch zeit zurueckstellen oder datum zurueckstellen irgendwie
--    manipuliert werden kann"
--
-- Der letzte Satz ist der Massstab fuer ALLES hier: die Geraeteuhr entscheidet
-- ueber nichts. Jede Frist wird gegen `now()` der Datenbank gerechnet, jeder
-- Zeitstempel wird serverseitig gesetzt oder ueberschrieben.
--
-- GEMESSENER AUSGANGSZUSTAND (24.08.2026, Produktivdatenbank):
--   communities                    6
--   community_members             44 Zeilen, 29 Personen
--     aeltester Beitritt   2026-06-16 16:52 UTC
--     juengster Beitritt   2026-08-23 19:40 UTC
--   community_messages            21 Zeilen, davon 9 mit deleted_at
--     mit updated_at               0   (die Spalte wird von NIEMANDEM gesetzt
--                                       ausser vom Pin-RPC)
--     angepinnt                    0
--     juenger als 6 Stunden        2
--   Bearbeiten-Funktion            existiert nicht (weder Client noch DB)
--   Systemzeilen fuer Beitritt/Austritt: existieren nicht
--   deleteMessage() setzte deleted_at auf DateTime.now() DES GERAETS
--   Rechte: anon UND authenticated hatten SELECT, INSERT, UPDATE, DELETE,
--           TRUNCATE, REFERENCES, TRIGGER auf community_messages
--
-- TRUNCATE ist dabei der schwerste Befund: TRUNCATE umgeht Row Level Security
-- vollstaendig. Ein einziger eingeloggter Nutzer haette alle Nachrichten aller
-- Communities loeschen koennen. Gleiche Falle wie am 26.07. bei road_incidents
-- und am 24.08. bei user_drive_sessions.


-- ############################################################################
-- TEIL A - WER KAM UND WER GING
-- ############################################################################
--
-- WARUM EINE EIGENE TABELLE UND KEINE SYSTEMZEILEN IN community_messages
--
-- Systemzeilen im Chat sind der uebliche Weg (WhatsApp, Discord, Slack). Fuer
-- DIESE Datenbank sind sie der teurere Weg, und zwar aus vier gemessenen
-- Gruenden:
--
--   1. ALTE APP-VERSIONEN BLEIBEN INSTALLIERT. Das ist in diesem Repo eine
--      feste Regel (CLAUDE.md, Abschnitt Laender-Klassifikation). Eine
--      Systemzeile in `community_messages` braucht ein Typ-Feld, das alte
--      Clients nicht kennen. Sie wuerden die Zeile als normale Nachricht des
--      Nutzers zeichnen, mit Avatar und Namen - es saehe so aus, als haette
--      die Person "Max ist beigetreten" selbst geschrieben. Ein neues Feld
--      kann man ausliefern; die installierte App von gestern nicht.
--
--   2. body IST NOT NULL, user_id IST NOT NULL MIT FREMDSCHLUESSEL. Der Text
--      der Systemzeile muesste also beim Schreiben festgelegt werden - in
--      einer App, die laut CLAUDE.md mehrsprachig werden soll (profiles.
--      app_language existiert bereits). Ein Ereignis mit `art` kann der Client
--      in jeder Sprache formulieren, ein eingefrorener deutscher Satz nicht.
--
--   3. DER HINWEISPUNKT WUERDE ZAEHLEN. `community_hinweispunkte()` zaehlt
--      jede Zeile in community_messages mit `deleted_at is null` und
--      `user_id <> ich` als ungelesen. Zehn Beitritte = zehn ungelesene
--      "Nachrichten" am Community-Punkt. Genau das Zumuellen, das der Auftrag
--      ausschliesst - und es waere nicht mal Anzeigelogik, sondern haette
--      unbemerkt den Zaehler verfaelscht.
--
--   4. DIE INSERT-POLICY MUESSTE AUFGEMACHT WERDEN.
--      `members_write_community_messages` verlangt `user_id = auth.uid()`.
--      Eine Systemzeile schreibt niemand selbst. Man muesste die Policy
--      erweitern oder mit SECURITY DEFINER daran vorbeischreiben - beides
--      lockert die Regel, die den Chat heute schuetzt.
--
-- Die eigene Tabelle bricht dagegen NICHTS: kein bestehendes SELECT, keine
-- Policy, kein Realtime-Kanal fasst sie an. Der Client mischt die Ereignisse
-- beim Zeichnen nach `am` in die Nachrichtenliste - dieselbe Darstellung wie
-- bei Systemzeilen, ohne deren Nebenwirkungen.
--
--
-- WARUM EIN TRIGGER UND NICHT EIN EINTRAG IN JEDER FUNKTION
--
-- Es gibt HEUTE sechs Wege in eine Community hinein und drei hinaus:
--   hinein   direkter INSERT (Policy users_join_public_communities),
--            join_community_with_code, join_community_with_code_v2,
--            accept_community_join_request, set_community_owner_member_on_insert
--            (der Gruender), Aufnahme durch einen Moderator
--   hinaus   leave_community, remove_community_member, Cascade
-- Neun Stellen zu pflegen heisst: die zehnte wird vergessen. Der Trigger auf
-- `community_members` sieht jeden Weg, auch jeden zukuenftigen.

create table if not exists public.community_mitglieder_verlauf (
  id             uuid        primary key default gen_random_uuid(),
  community_id   uuid        not null references public.communities(id) on delete cascade,
  user_id        uuid        not null references public.profiles(id)    on delete cascade,
  -- 'beitritt'  jemand ist dazugekommen
  -- 'austritt'  jemand ist selbst gegangen
  -- 'entfernt'  ein Admin oder Moderator hat jemanden entfernt
  art            text        not null,
  -- Wer es ausgeloest hat. Bei 'entfernt' der Admin, bei 'beitritt' meist die
  -- Person selbst. NULL = kein angemeldeter Aufrufer (Serverjob, Support).
  ausgeloest_von uuid        references public.profiles(id) on delete set null,
  -- IMMER Serverzeit. Es gibt keinen Weg, hier einen Wert mitzuschicken:
  -- authenticated hat auf dieser Tabelle nur SELECT (siehe unten).
  am             timestamptz not null default now(),
  -- true = beim Einfuehren der Tabelle aus community_members.created_at
  -- nachgetragen, nicht live beobachtet. Siehe Altbestand weiter unten.
  nachgetragen   boolean     not null default false,
  constraint community_mitglieder_verlauf_art_chk
    check (art in ('beitritt', 'austritt', 'entfernt'))
);

comment on table public.community_mitglieder_verlauf is
  '2026-08-24: Verlauf der Mitgliedschaften einer Community (wer kam, wer '
  'ging). Bewusst NICHT als Systemzeile in community_messages - das haette '
  'alte App-Versionen die Zeile als echte Nachricht zeichnen lassen und den '
  'Hinweispunkt verfaelscht. Geschrieben ausschliesslich vom Trigger '
  'trg_community_mitgliedschaft_protokoll.';

comment on column public.community_mitglieder_verlauf.nachgetragen is
  'true = am 24.08. aus community_members.created_at nachgetragen. Der '
  'Zeitstempel ist echt, aber es ist kein beobachtetes Ereignis: Personen, '
  'die vor dem 24.08. beigetreten UND wieder gegangen sind, fehlen '
  'zwangslaeufig ganz.';

-- Der Chat liest den Verlauf einer Community chronologisch, genau wie die
-- Nachrichten. Der zweite Index bedient die Missbrauchsbremse (Zaehlung je
-- Person und Community in den letzten 24 Stunden).
create index if not exists idx_community_verlauf_chronologisch
  on public.community_mitglieder_verlauf (community_id, am desc);
create index if not exists idx_community_verlauf_person
  on public.community_mitglieder_verlauf (community_id, user_id, am desc);
-- Die beiden folgenden decken die Fremdschluessel ab. Ohne sie muss Postgres
-- bei jeder Kontoloeschung die ganze Tabelle lesen (Befund
-- `unindexed_foreign_keys` des Advisors).
create index if not exists idx_community_verlauf_konto
  on public.community_mitglieder_verlauf (user_id);
create index if not exists idx_community_verlauf_ausgeloest_von
  on public.community_mitglieder_verlauf (ausgeloest_von)
  where ausgeloest_von is not null;

alter table public.community_mitglieder_verlauf enable row level security;

-- Lesen darf, wer in der Community ist. Wer gegangen ist, sieht den Chat
-- ohnehin nicht mehr (members_read_community_messages verlangt dasselbe).
drop policy if exists "verlauf_lesen_als_mitglied" on public.community_mitglieder_verlauf;
create policy "verlauf_lesen_als_mitglied"
  on public.community_mitglieder_verlauf
  for select
  -- (select auth.uid()) statt auth.uid(): so wertet Postgres den Aufruf EINMAL
  -- je Abfrage aus statt je Zeile. Ohne die Klammern meldet der Advisor
  -- `auth_rls_initplan` - der Befund, den dieses Projekt 111 Mal mitschleppt.
  using (public.is_community_member(community_id, (select auth.uid())));

-- Es gibt ABSICHTLICH keine INSERT-, UPDATE- oder DELETE-Policy. Der Verlauf
-- ist ein Protokoll: wer ihn schreiben oder nachtraeglich glaetten koennte,
-- macht ihn wertlos. Geschrieben wird nur vom Trigger, der als Eigentuemer
-- laeuft und RLS damit nicht durchlaeuft.
--
-- Supabase vergibt fuer neue Tabellen per Default-Privileges automatisch alle
-- Rechte an anon und authenticated. Deshalb hier zuerst alles entziehen und
-- dann genau ein Recht zurueckgeben.
revoke all on table public.community_mitglieder_verlauf from anon, authenticated;
grant select on table public.community_mitglieder_verlauf to authenticated;


-- ----------------------------------------------------------------------------
-- Der Trigger, der jeden Beitritt und jeden Austritt sieht
-- ----------------------------------------------------------------------------
--
-- MISSBRAUCH: "wer zehnmal ein- und austritt, darf den Chat nicht zumuellen."
-- Die Bremse zaehlt die Ereignisse derselben Person in derselben Community
-- in den letzten 24 Stunden. Ab dem sechsten wird nichts mehr geschrieben.
--
-- Warum ausgerechnet sechs und warum eine GERADE Zahl: Beitritt und Austritt
-- treten immer als Paar auf. Bei einer geraden Obergrenze endet der Verlauf
-- nie mitten in einem Paar ("beigetreten" ohne das zugehoerige "gegangen"),
-- was fuer den Leser aussaehe, als waere die Person noch da. Sechs sind drei
-- volle Runden - genug, um ein echtes Hin und Her abzubilden (Netzabbruch,
-- versehentlicher Austritt), und wenig genug, dass ein Trollversuch nach
-- Sekunden aufhoert, Spuren zu hinterlassen. Die Mitgliedschaft selbst bleibt
-- davon unberuehrt: nur das Protokoll schweigt, der Beitritt gilt.
--
-- SECURITY DEFINER, weil die Funktion in eine Tabelle schreibt, auf der der
-- Aufrufer bewusst kein INSERT-Recht hat.
create or replace function public.protokolliere_community_mitgliedschaft()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_community uuid := coalesce(new.community_id, old.community_id);
  v_person    uuid := coalesce(new.user_id, old.user_id);
  v_uid       uuid := auth.uid();
  v_anzahl    int;
  v_art       text;
begin
  -- CASCADE-SCHUTZ. Wird eine Community oder ein Konto geloescht, raeumt
  -- Postgres community_members mit weg und dieser Trigger feuert fuer jede
  -- Zeile. Ein Protokolleintrag waere dann ein Fremdschluessel auf eine Zeile,
  -- die im selben Befehl verschwindet - im besten Fall wird er sofort
  -- mitgeloescht, im schlechtesten scheitert die Kontoloeschung an der
  -- Fremdschluesselpruefung. Beim Cascade ist die Elternzeile hier bereits
  -- nicht mehr sichtbar, das ist die verlaessliche Erkennung.
  if not exists (select 1 from public.communities where id = v_community) then
    return coalesce(new, old);
  end if;
  if not exists (select 1 from public.profiles where id = v_person) then
    return coalesce(new, old);
  end if;

  select count(*) into v_anzahl
  from public.community_mitglieder_verlauf v
  where v.community_id = v_community
    and v.user_id = v_person
    and v.am > now() - interval '24 hours';

  if v_anzahl >= 6 then
    return coalesce(new, old);
  end if;

  if tg_op = 'INSERT' then
    v_art := 'beitritt';
  elsif v_uid is null or v_uid = v_person then
    -- Kein angemeldeter Aufrufer oder die Person selbst: sie ist gegangen.
    v_art := 'austritt';
  else
    -- Jemand anderes hat die Zeile entfernt - das ist remove_community_member.
    -- SECURITY DEFINER aendert auth.uid() NICHT, die Funktion liest die
    -- JWT-Angabe der Anfrage. Der Admin ist hier also korrekt sichtbar.
    v_art := 'entfernt';
  end if;

  insert into public.community_mitglieder_verlauf
    (community_id, user_id, art, ausgeloest_von)
  values (v_community, v_person, v_art, v_uid);

  return coalesce(new, old);
end;
$$;

comment on function public.protokolliere_community_mitgliedschaft() is
  '2026-08-24: Schreibt je Beitritt und Austritt eine Zeile in '
  'community_mitglieder_verlauf. Haengt am Trigger statt an den neun '
  'Ein- und Ausstiegsfunktionen, damit kein Weg vergessen wird. Bremse: '
  'hoechstens 6 Ereignisse je Person und Community in 24 Stunden.';

-- Wiederkehrende Falle in diesem Projekt: eine Triggerfunktion, die als RPC
-- offensteht. Ein Trigger braucht das EXECUTE-Recht des Aufrufers nicht.
revoke all on function public.protokolliere_community_mitgliedschaft() from public;
revoke all on function public.protokolliere_community_mitgliedschaft() from anon;
revoke all on function public.protokolliere_community_mitgliedschaft() from authenticated;

drop trigger if exists trg_community_mitgliedschaft_protokoll on public.community_members;
create trigger trg_community_mitgliedschaft_protokoll
  after insert or delete on public.community_members
  for each row
  execute function public.protokolliere_community_mitgliedschaft();


-- ----------------------------------------------------------------------------
-- ALTBESTAND: 44 Mitgliedschaften ohne einen einzigen festgehaltenen Beitritt
-- ----------------------------------------------------------------------------
--
-- Was zeigen wir fuer die? Die ehrliche Antwort steht bereits in der
-- Datenbank: `community_members.created_at` IST der Beitrittszeitpunkt, er
-- wurde nur nie als Ereignis gefuehrt. Also wird er nachgetragen - mit dem
-- echten Zeitstempel (16.06. bis 23.08.) und mit `nachgetragen = true`, damit
-- niemand spaeter glaubt, das sei live beobachtet worden.
--
-- WAS SICH NICHT NACHTRAGEN LAESST: Wer vor heute beigetreten UND wieder
-- gegangen ist, hinterliess keine Spur - die Zeile in community_members ist
-- weg. Diese Faelle fehlen fuer immer. Der Verlauf beginnt fuer jede
-- Community mit dem Stand von heute; alles Weitere waechst ab jetzt.
--
-- IDEMPOTENZ: Beim zweiten Lauf trifft `not exists` alle Zeilen, es wird
-- nichts doppelt eingetragen.
insert into public.community_mitglieder_verlauf
  (community_id, user_id, art, ausgeloest_von, am, nachgetragen)
select m.community_id, m.user_id, 'beitritt', null, m.created_at, true
from public.community_members m
where not exists (
  select 1 from public.community_mitglieder_verlauf v
  where v.community_id = m.community_id
    and v.user_id = m.user_id
);

-- Realtime: der Chat soll einen Beitritt sofort zeigen, ohne dass jemand die
-- Seite neu laedt. Muster von road_incidents (20260724120000).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'community_mitglieder_verlauf'
  ) then
    alter publication supabase_realtime add table public.community_mitglieder_verlauf;
  end if;
end $$;


-- ############################################################################
-- TEIL B - NACHRICHTEN BEARBEITEN, SECHS STUNDEN LANG
-- ############################################################################
--
-- WIRD DER URSPRUNGSTEXT AUFGEHOBEN? JA - ABER NICHT SICHTBAR.
--
-- Vucko begruendet das Bearbeiten-Fenster damit, dass niemand nachtraeglich
-- etwas anderes behaupten koennen soll. Ein sichtbares "bearbeitet" reicht
-- dafuer im Streitfall nicht: es sagt, DASS geaendert wurde, nicht WAS
-- dastand. Also wird der urspruengliche Text aufgehoben.
--
-- Aufgehoben wird NUR die erste Fassung, nicht jede Zwischenstufe. Begruendung:
--   * Der Beweiswert liegt in "was stand da, als die anderen es gelesen
--     haben" - das ist die erste Fassung. Zwischenstufen innerhalb von sechs
--     Stunden beantworten keine Frage, die sonst offen bliebe.
--   * Eine Historientabelle waere bei 21 Nachrichten reine Vorratshaltung
--     und braeuchte eigene Policies, eigene Indizes und eine eigene
--     Loeschregel bei Kontoloeschung.
--   * Eine Spalte kostet genau eine Kopie des Textes (Schnitt: 76 Zeichen).
--
-- LESEN DARF DEN URSPRUNGSTEXT NIEMAND UEBER DIE APP. Sonst waere das
-- Bearbeiten sinnlos: wer einen Tippfehler ausbessert, moechte nicht, dass
-- jeder andere den Fehler ueber die rohe Schnittstelle weiter abrufen kann.
-- Deshalb wird das Leserecht auf community_messages spaltenweise vergeben -
-- dasselbe Mittel, mit dem am 23.08. `communities.invite_code` geschuetzt
-- wurde. `original_body` bleibt allein dem service_role vorbehalten (Support
-- und Moderation).
alter table public.community_messages
  add column if not exists bearbeitet_am timestamptz,
  add column if not exists original_body text;

comment on column public.community_messages.bearbeitet_am is
  '2026-08-24: Wann zuletzt bearbeitet wurde, NULL = nie. Wird ausschliesslich '
  'vom Trigger trg_wacht_ueber_community_nachricht auf now() gesetzt; ein '
  'mitgeschickter Wert wird verworfen.';

comment on column public.community_messages.original_body is
  '2026-08-24: Der Text der ERSTEN Fassung, gesetzt beim ersten Bearbeiten. '
  'NICHT fuer Mitglieder lesbar (spaltenweises SELECT-Recht) - nur '
  'service_role sieht ihn. Beweismittel, keine Anzeige.';


-- ----------------------------------------------------------------------------
-- Spaltenweises Leserecht
-- ----------------------------------------------------------------------------
--
-- ACHTUNG FUER SPAETER: Ab hier braucht JEDE neue Spalte auf
-- public.community_messages ein eigenes `grant select`. Wird das vergessen,
-- meldet PostgREST fuer die neue Spalte "permission denied", NICHT "column
-- does not exist" - der `_isMissingColumn`-Fallback im Client greift dann
-- nicht. Genau diese Warnung steht schon ueber `_communitySelect` in
-- community_chat_service.dart.
--
-- Geprueft am 24.08.: KEINE Stelle im Client liest community_messages mit
-- `select('*')` (grep ueber lib/), keine Edge Function und keine Sicht
-- (pg_get_viewdef ueber alle Sichten in public) fasst die Tabelle an.
--
-- anon verliert das Leserecht ganz. Es hat ihm nie genuetzt:
-- `members_read_community_messages` verlangt is_community_member(.., auth.uid())
-- und auth.uid() ist fuer anon NULL.
revoke select on public.community_messages from anon, authenticated;
grant select (
  id, community_id, user_id, body, created_at, updated_at, deleted_at,
  reply_to_message_id, route_attachment, pinned_at, pinned_by, bearbeitet_am
) on public.community_messages to authenticated;


-- ############################################################################
-- TEIL C - RECHTE ENTZIEHEN, BEVOR REGELN GEBAUT WERDEN
-- ############################################################################
--
-- Eine Regel im Trigger nuetzt nichts, solange daneben ein Recht steht, das
-- an ihr vorbeifuehrt.
--
--   TRUNCATE  umgeht RLS vollstaendig - ein Nutzer haette alle Nachrichten
--             aller Communities loeschen koennen.
--   DELETE    ist das echte Loeschen der Zeile. Der Client benutzt es
--             nirgends (grep ueber lib/: kein `.delete()` auf
--             community_messages), aber es wuerde `original_body` und den
--             gesamten Nachweis spurlos entfernen. Der App-Weg ist das weiche
--             Loeschen ueber `deleted_at`, das jede Abfrage bereits
--             ausblendet (`isFilter('deleted_at', null)`).
--   anon      brauchte nie INSERT, UPDATE oder DELETE.
--
-- delete_community(), delete_current_user() und die Fremdschluessel-Cascades
-- sind davon NICHT betroffen: SECURITY-DEFINER-Funktionen laufen mit den
-- Rechten ihres Eigentuemers, und eine Cascade fuehrt Postgres selbst aus.
revoke truncate, references, trigger on public.community_messages from anon, authenticated;
revoke truncate, references, trigger on public.community_members  from anon, authenticated;
revoke truncate, references, trigger on public.communities        from anon, authenticated;
revoke delete on public.community_messages from anon, authenticated;
revoke insert, update, delete on public.community_messages from anon;
revoke insert, update, delete on public.community_members  from anon;
revoke delete on public.communities from anon;

-- Die DELETE-Policy wird durch eine ausdrueckliche Sperre ersetzt, damit im
-- Katalog steht, WARUM hier nichts geht. Muster: community_members hat seit
-- dem 09.06. dieselbe Sperre ("community_members_delete_via_rpc").
drop policy if exists "authors_delete_community_messages" on public.community_messages;
drop policy if exists "community_messages_kein_hartes_loeschen" on public.community_messages;
create policy "community_messages_kein_hartes_loeschen"
  on public.community_messages
  for delete
  using (false);


-- ############################################################################
-- TEIL D - LOESCHEN NUR FUER MICH
-- ############################################################################
--
-- "nur fuer mich" darf NICHT auf dem Geraet liegen. Genau dieser Fehler ist
-- heute Nacht bei der Kachel-Anordnung der Startseite aufgeflogen
-- (20260824140000): SharedPreferences bedeutet, dass ein neues Handy oder
-- eine Neuinstallation alles zurueckdreht. Bei einer ausgeblendeten Nachricht
-- waere das besonders unangenehm - sie kaeme wieder, obwohl die Person sie
-- ausdruecklich weggeraeumt hat.
--
-- Eine Zeile je (Person, Nachricht). Bei 21 Nachrichten und 29 Personen ist
-- die Tabelle auf absehbare Zeit winzig; `community_id` liegt mit in der
-- Zeile, damit der Client beim Oeffnen EINER Community nur deren
-- ausgeblendete Kennungen holt und nicht alle.
create table if not exists public.community_nachricht_ausgeblendet (
  user_id      uuid        not null references public.profiles(id)           on delete cascade,
  message_id   uuid        not null references public.community_messages(id) on delete cascade,
  community_id uuid        not null references public.communities(id)        on delete cascade,
  am           timestamptz not null default now(),
  constraint community_nachricht_ausgeblendet_pkey primary key (user_id, message_id)
);

comment on table public.community_nachricht_ausgeblendet is
  '2026-08-24: "Nur fuer mich geloescht" wie bei WhatsApp. Am KONTO, nicht am '
  'Geraet - sonst kaeme die Nachricht nach einer Neuinstallation zurueck. Der '
  'Client zieht beim Oeffnen einer Community die eigenen Kennungen und laesst '
  'diese Nachrichten aus.';

create index if not exists idx_community_ausgeblendet_person
  on public.community_nachricht_ausgeblendet (user_id, community_id);
-- Fremdschluessel-Abdeckung: message_id steckt zwar im Primaerschluessel,
-- aber nicht an fuehrender Stelle - fuer das CASCADE beim Loeschen einer
-- Nachricht nuetzt er deshalb nichts.
create index if not exists idx_community_ausgeblendet_nachricht
  on public.community_nachricht_ausgeblendet (message_id);
create index if not exists idx_community_ausgeblendet_community
  on public.community_nachricht_ausgeblendet (community_id);

alter table public.community_nachricht_ausgeblendet enable row level security;

drop policy if exists "ausgeblendet_lesen_eigene" on public.community_nachricht_ausgeblendet;
create policy "ausgeblendet_lesen_eigene"
  on public.community_nachricht_ausgeblendet
  for select
  using (user_id = (select auth.uid()));

-- Ausblenden darf nur, wer die Nachricht ueberhaupt sehen darf. Sonst koennte
-- jemand Kennungen fremder Communities sammeln, indem er ausprobiert, welcher
-- INSERT durchgeht.
drop policy if exists "ausgeblendet_setzen_eigene" on public.community_nachricht_ausgeblendet;
create policy "ausgeblendet_setzen_eigene"
  on public.community_nachricht_ausgeblendet
  for insert
  with check (
    user_id = (select auth.uid())
    and public.is_community_message_member(message_id, (select auth.uid()))
  );

-- Zuruecknehmen ist erlaubt (die App bietet es heute nicht an, aber es ist
-- die eigene Anzeige und ein Support-Fall braucht sonst service_role).
drop policy if exists "ausgeblendet_zuruecknehmen_eigene" on public.community_nachricht_ausgeblendet;
create policy "ausgeblendet_zuruecknehmen_eigene"
  on public.community_nachricht_ausgeblendet
  for delete
  using (user_id = (select auth.uid()));

revoke all on table public.community_nachricht_ausgeblendet from anon, authenticated;
grant select, insert, delete on table public.community_nachricht_ausgeblendet to authenticated;


-- ############################################################################
-- TEIL E - DER WAECHTER: HIER ENTSCHEIDET DIE SERVERUHR
-- ############################################################################
--
-- Warum die Regeln im TRIGGER stehen und nicht (nur) im RPC:
-- Ein RPC ist eine Tuer. Die rohe PostgREST-Schnittstelle ist die zweite Tuer
-- und sie steht offen, solange authenticated UPDATE auf der Tabelle hat -
-- und das braucht sie, weil ALTE APP-VERSIONEN ihr weiches Loeschen als
-- direktes UPDATE schicken (community_chat_service.dart, deleteMessage). Wer
-- die Frist nur im RPC prueft, hat sie nicht geprueft.
--
-- Der Trigger sitzt an der Tabelle. Damit gilt fuer jeden Weg dieselbe Regel,
-- und die alte App bleibt benutzbar - ihr geraetezeit-gestempeltes
-- `deleted_at` wird hier stillschweigend auf die Serverzeit gesetzt.
--
-- SECURITY INVOKER mit Absicht: die Funktion liest nur OLD/NEW und auth.uid()
-- und braucht keine fremden Rechte. Als SECURITY DEFINER haette der Advisor
-- sie zu Recht bemaengelt - derselbe Befund kam am 19.08. schon einmal.
create or replace function public.wacht_ueber_community_nachricht()
returns trigger
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $$
declare
  v_uid uuid := auth.uid();
begin
  -- Kein angemeldeter Aufrufer = Serverjob, Migration oder Support ueber
  -- service_role. Dieselbe Ausnahme wie bei guard_starter_bonus_ende und
  -- guard_home_layout_stand, damit ein Support-Fall korrigierbar bleibt.
  if v_uid is null then
    return new;
  end if;

  -- 1) Was sich NIE aendert. Kein Umhaengen in eine andere Community, kein
  --    Unterschieben eines anderen Verfassers und vor allem: kein neues
  --    created_at. Waere created_at frei setzbar, koennte man die Frist
  --    beliebig oft verlaengern - genau die Manipulation, die Vucko meint.
  new.id                 := old.id;
  new.community_id       := old.community_id;
  new.user_id            := old.user_id;
  new.created_at         := old.created_at;
  new.reply_to_message_id := old.reply_to_message_id;
  new.route_attachment   := old.route_attachment;

  -- 2) Diese beiden setzt ausschliesslich dieser Trigger. Ein mitgeschickter
  --    Wert wird verworfen - sonst koennte man `bearbeitet_am` auf NULL
  --    zuruecksetzen und die Kennzeichnung waere wertlos, oder original_body
  --    ueberschreiben und der Nachweis waere weg.
  new.bearbeitet_am := old.bearbeitet_am;
  new.original_body := old.original_body;

  -- 3) Loeschen fuer alle.
  if old.deleted_at is null and new.deleted_at is not null then
    -- Wer darf das? GENAU WIE HEUTE: der Verfasser, der Inhaber und die
    -- Moderatoren. (Achtung Namensfalle: is_community_owner() liefert auch
    -- fuer 'moderator' true. can_moderate_community() ist dieselbe Menge und
    -- heisst ehrlicher.) Bewusst NICHT geaendert - eine stille Verschaerfung
    -- der Moderationsrechte gehoert nicht in diesen Auftrag.
    if old.user_id <> v_uid
       and not public.can_moderate_community(old.community_id, v_uid) then
      raise exception 'Nur der Verfasser oder ein Admin kann diese Nachricht fuer alle loeschen.'
        using errcode = '42501';
    end if;
    -- DIE UHR DES GERAETS WIRD VERWORFEN. Die alte App schickt hier
    -- DateTime.now() mit; ab jetzt zaehlt ausschliesslich die Serverzeit.
    new.deleted_at := now();
  elsif old.deleted_at is not null then
    -- Einmal geloescht bleibt geloescht: kein Wiederherstellen, kein
    -- Umdatieren. (Die UPDATE-Policy laesst solche Zeilen ohnehin nicht mehr
    -- durch; das hier ist die zweite Schicht.)
    new.deleted_at := old.deleted_at;
  end if;

  -- 4) Anpinnen bleibt Moderationssache. set_community_message_pinned() prueft
  --    das selbst und meldet einen eigenen Fehler; hier wird nur still
  --    zurueckgedreht, was ueber die rohe Schnittstelle kommt.
  if (new.pinned_at is distinct from old.pinned_at
      or new.pinned_by is distinct from old.pinned_by)
     and not public.can_moderate_community(old.community_id, v_uid) then
    new.pinned_at := old.pinned_at;
    new.pinned_by := old.pinned_by;
  end if;

  -- 5) Bearbeiten.
  if new.body is distinct from old.body then
    -- Nur der Verfasser. Ein Moderator darf loeschen und anpinnen, aber
    -- niemandem Worte in den Mund legen.
    if old.user_id <> v_uid then
      raise exception 'Nur der Verfasser kann seine Nachricht bearbeiten.'
        using errcode = '42501';
    end if;
    if old.deleted_at is not null or new.deleted_at is not null then
      raise exception 'Eine geloeschte Nachricht kann nicht mehr bearbeitet werden.'
        using errcode = '42501';
    end if;
    -- DIE FRIST. Gerechnet gegen now() der Datenbank und created_at der
    -- Datenbank. Beide Werte kann der Client nicht beeinflussen: created_at
    -- hat `default now()` und wird in Schritt 1 festgenagelt.
    if now() - old.created_at > interval '6 hours' then
      raise exception 'Die Bearbeitungsfrist von 6 Stunden ist abgelaufen.'
        using errcode = '42501';
    end if;
    new.body := btrim(new.body);
    if char_length(new.body) < 1 then
      raise exception 'Die Nachricht darf nicht leer sein.'
        using errcode = '22000';
    end if;
    -- Die Obergrenze von 2.000 Zeichen deckt bereits der bestehende
    -- CHECK community_messages_body_length ab (identisch mit
    -- AppInputLimits.communityMessageMaxLength).
    new.bearbeitet_am := now();
    new.original_body := coalesce(old.original_body, old.body);
    new.updated_at    := now();
  end if;

  return new;
end;
$$;

comment on function public.wacht_ueber_community_nachricht() is
  '2026-08-24: Setzt die Regeln fuer jedes UPDATE auf community_messages '
  'durch - Bearbeitungsfrist 6 Stunden gegen die SERVERZEIT, Loeschzeitpunkt '
  'immer now(), unveraenderliche Felder, Kennzeichnung als bearbeitet. Sitzt '
  'am Trigger und nicht im RPC, weil alte App-Versionen weiterhin direkt per '
  'UPDATE loeschen.';

revoke all on function public.wacht_ueber_community_nachricht() from public;
revoke all on function public.wacht_ueber_community_nachricht() from anon;
revoke all on function public.wacht_ueber_community_nachricht() from authenticated;

drop trigger if exists trg_wacht_ueber_community_nachricht on public.community_messages;
create trigger trg_wacht_ueber_community_nachricht
  before update on public.community_messages
  for each row
  execute function public.wacht_ueber_community_nachricht();


-- ----------------------------------------------------------------------------
-- Der zweite Waechter: das SCHREIBEN einer Nachricht
-- ----------------------------------------------------------------------------
--
-- Die Frist rechnet gegen `created_at`. Wer `created_at` beim EINFUEGEN frei
-- waehlen kann, hat die Frist ausgehebelt, bevor sie beginnt: eine Nachricht
-- mit `created_at = now() + 400 Tage` ist ueber ein Jahr lang bearbeitbar.
-- Gemessen am 24.08.: authenticated hatte INSERT auf ALLEN Spalten, und die
-- Gegenprobe hat genau diesen Zeitstempel gesetzt bekommen (2027-09-28).
--
-- Der Client schickt heute nur community_id, user_id, body und optional
-- reply_to_message_id/route_attachment (community_chat_service.dart,
-- sendMessage) - fuer die App aendert sich also nichts.
create or replace function public.setze_community_nachricht_grundwerte()
returns trigger
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  -- Die Uhr des Geraets zaehlt nicht. Auch nicht beim Anlegen.
  new.created_at    := now();
  new.updated_at    := null;
  -- Eine neue Nachricht ist nicht bearbeitet, nicht geloescht, nicht
  -- angepinnt - egal, was mitgeschickt wurde.
  new.bearbeitet_am := null;
  new.original_body := null;
  new.deleted_at    := null;
  new.pinned_at     := null;
  new.pinned_by     := null;
  return new;
end;
$$;

comment on function public.setze_community_nachricht_grundwerte() is
  '2026-08-24: Setzt created_at beim Einfuegen auf die Serverzeit und raeumt '
  'bearbeitet_am, original_body, deleted_at und die Pin-Felder weg. Ohne das '
  'koennte man die 6-Stunden-Frist mit einem created_at in der Zukunft '
  'beliebig verlaengern.';

revoke all on function public.setze_community_nachricht_grundwerte() from public;
revoke all on function public.setze_community_nachricht_grundwerte() from anon;
revoke all on function public.setze_community_nachricht_grundwerte() from authenticated;

drop trigger if exists trg_setze_community_nachricht_grundwerte on public.community_messages;
create trigger trg_setze_community_nachricht_grundwerte
  before insert on public.community_messages
  for each row
  execute function public.setze_community_nachricht_grundwerte();


-- ----------------------------------------------------------------------------
-- Die UPDATE-Policy
-- ----------------------------------------------------------------------------
--
-- Bisher: `authors_update_community_messages` erlaubte dem Verfasser JEDES
-- Update, ohne Frist und ohne zu pruefen, was sich aendert.
--
-- Eine Policy kann OLD nicht sehen und deshalb weder "nur der Text hat sich
-- geaendert" noch "die Frist laeuft noch" ausdruecken - das leistet der
-- Waechter oben. Was die Policy leisten KANN und ab jetzt leistet: eine
-- bereits fuer alle geloeschte Nachricht ist endgueltig. Sie kommt gar nicht
-- mehr bis zum Trigger.
--
-- WITH CHECK darf `deleted_at is null` NICHT verlangen - beim Loeschen ist der
-- neue Wert ja gerade gesetzt.
drop policy if exists "authors_update_community_messages" on public.community_messages;
create policy "authors_update_community_messages"
  on public.community_messages
  for update
  using (
    deleted_at is null
    and (
      user_id = (select auth.uid())
      or public.can_moderate_community(community_id, (select auth.uid()))
    )
  )
  with check (
    user_id = (select auth.uid())
    or public.can_moderate_community(community_id, (select auth.uid()))
  );


-- ############################################################################
-- TEIL F - DIE BEIDEN AUFRUFE FUER DEN CLIENT
-- ############################################################################
--
-- Beide sind SECURITY INVOKER: sie brauchen keine fremden Rechte, RLS und der
-- Waechter greifen also zusaetzlich. Ihr Zweck ist NICHT die Absicherung
-- (die liegt am Trigger), sondern eine klare deutsche Fehlermeldung und ein
-- Rueckgabewert, mit dem die Oberflaeche sofort weiterarbeiten kann.

create or replace function public.community_nachricht_bearbeiten(
  p_message_id uuid,
  p_body       text
)
returns timestamptz
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $$
declare
  v_uid        uuid := auth.uid();
  v_user_id    uuid;
  v_created_at timestamptz;
  v_deleted_at timestamptz;
  v_neu        timestamptz;
begin
  if v_uid is null then
    raise exception 'Bitte melde dich an.' using errcode = '42501';
  end if;

  -- Lesen darf hier nur, wer Mitglied ist (RLS auf community_messages).
  select m.user_id, m.created_at, m.deleted_at
    into v_user_id, v_created_at, v_deleted_at
  from public.community_messages m
  where m.id = p_message_id;

  if not found then
    raise exception 'Nachricht nicht gefunden.' using errcode = 'P0002';
  end if;
  if v_user_id <> v_uid then
    raise exception 'Nur der Verfasser kann seine Nachricht bearbeiten.'
      using errcode = '42501';
  end if;
  if v_deleted_at is not null then
    raise exception 'Eine geloeschte Nachricht kann nicht mehr bearbeitet werden.'
      using errcode = '42501';
  end if;
  -- Serverzeit gegen Serverzeitstempel. Dieselbe Rechnung wie im Waechter;
  -- hier nur, damit die Meldung freundlich ist statt roh.
  if now() - v_created_at > interval '6 hours' then
    raise exception 'Die Bearbeitungsfrist von 6 Stunden ist abgelaufen.'
      using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_body, ''))) < 1 then
    raise exception 'Die Nachricht darf nicht leer sein.' using errcode = '22000';
  end if;
  if char_length(btrim(p_body)) > 2000 then
    raise exception 'Nachricht ist zu lang.' using errcode = '22000';
  end if;

  update public.community_messages
     set body = btrim(p_body)
   where id = p_message_id
  returning bearbeitet_am into v_neu;

  return v_neu;
end;
$$;

comment on function public.community_nachricht_bearbeiten(uuid, text) is
  '2026-08-24: Bearbeitet die eigene Nachricht innerhalb von 6 Stunden nach '
  'created_at. Frist und Kennzeichnung setzt der Trigger '
  'trg_wacht_ueber_community_nachricht durch; diese Funktion liefert nur die '
  'lesbare Fehlermeldung und das neue bearbeitet_am zurueck.';

revoke all on function public.community_nachricht_bearbeiten(uuid, text) from public;
revoke all on function public.community_nachricht_bearbeiten(uuid, text) from anon;
grant execute on function public.community_nachricht_bearbeiten(uuid, text) to authenticated;


-- ----------------------------------------------------------------------------
-- Loeschen: fuer alle oder nur fuer mich
-- ----------------------------------------------------------------------------
--
-- GILT FUER "FUER ALLE" AUCH EINE FRIST? NEIN - bewusst nicht.
--
-- Vucko hat die sechs Stunden ausdruecklich nur beim Bearbeiten genannt. Die
-- beiden Faelle sind auch nicht dasselbe:
--   * Bearbeiten VERAENDERT eine Aussage. Ohne Frist koennte jemand Wochen
--     spaeter behaupten, er habe etwas anderes geschrieben. Die Frist
--     schuetzt die anderen.
--   * Loeschen ENTFERNT eine Aussage. Wer merkt, dass er seine Adresse, sein
--     Kennzeichen oder ein Foto in einen offenen Chat gestellt hat, merkt das
--     oft erst Tage spaeter. Eine Frist wuerde hier die Person schuetzen, die
--     man eigentlich schuetzen will - vor sich selbst.
-- Ausserdem ist "unbefristet" der HEUTIGE Zustand (die alte deleteMessage
-- kennt keine Frist). Eine neue Frist waere eine stille Verschaerfung.
create or replace function public.community_nachricht_loeschen(
  p_message_id uuid,
  p_fuer_alle  boolean default false
)
returns void
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $$
declare
  v_uid          uuid := auth.uid();
  v_user_id      uuid;
  v_community_id uuid;
  v_deleted_at   timestamptz;
begin
  if v_uid is null then
    raise exception 'Bitte melde dich an.' using errcode = '42501';
  end if;

  select m.user_id, m.community_id, m.deleted_at
    into v_user_id, v_community_id, v_deleted_at
  from public.community_messages m
  where m.id = p_message_id;

  if not found then
    raise exception 'Nachricht nicht gefunden.' using errcode = 'P0002';
  end if;

  if p_fuer_alle then
    if v_deleted_at is not null then
      return;  -- schon weg, kein Fehler
    end if;
    if v_user_id <> v_uid
       and not public.can_moderate_community(v_community_id, v_uid) then
      raise exception 'Nur der Verfasser oder ein Admin kann diese Nachricht fuer alle loeschen.'
        using errcode = '42501';
    end if;
    -- Der Waechter setzt den Zeitpunkt auf now(); was hier steht, ist nur der
    -- Anlass. Absichtlich trotzdem now() und nicht irgendein Platzhalter.
    update public.community_messages
       set deleted_at = now()
     where id = p_message_id;
  else
    -- Nur fuer mich: JEDES Mitglied darf jede Nachricht aus der eigenen
    -- Ansicht raeumen, auch fremde. Genau wie bei WhatsApp.
    insert into public.community_nachricht_ausgeblendet
      (user_id, message_id, community_id)
    values (v_uid, p_message_id, v_community_id)
    on conflict (user_id, message_id) do nothing;
  end if;
end;
$$;

comment on function public.community_nachricht_loeschen(uuid, boolean) is
  '2026-08-24: p_fuer_alle = true setzt deleted_at (Serverzeit, unbefristet, '
  'Verfasser oder Moderation). p_fuer_alle = false blendet die Nachricht nur '
  'fuer den Aufrufer aus - am Konto, nicht am Geraet.';

revoke all on function public.community_nachricht_loeschen(uuid, boolean) from public;
revoke all on function public.community_nachricht_loeschen(uuid, boolean) from anon;
grant execute on function public.community_nachricht_loeschen(uuid, boolean) to authenticated;


-- ############################################################################
-- TEIL G - DIE CHAT-ART
-- ############################################################################
--
-- GEHOERT DAS IN DIE DATENBANK ODER ANS GERAET?
--
-- Ans Konto. Die Frage ist immer dieselbe: haengt die Einstellung am GERAET
-- (Bildschirmgroesse, Systemdesign, Lautstaerke) oder an der PERSON? Wie
-- jemand Chats lesen moechte, haengt an der Person. Genau deshalb ist heute
-- Nacht die Kachel-Anordnung der Startseite von den SharedPreferences auf
-- profiles.home_layout umgezogen (20260824140000): "deine Anordnung wandert
-- nicht aufs neue Handy" war der Mangel, und hier waere er derselbe.
--
-- WARUM EINE SPALTE AUF profiles UND KEINE EIGENE TABELLE: dieselbe
-- Abwaegung wie am 19.08. beim Starter-Paket. Es gibt genau EINEN Wert je
-- Konto, keine Historie, nichts zu verknuepfen, und geschrieben wird er ein
-- paar Mal im Leben eines Kontos - nicht bei jedem Reiterwechsel wie der
-- Lesestand, fuer den deshalb bewusst eine eigene Tabelle gebaut wurde.
--
-- Kein Kein-Rueckdreh-Waechter wie bei home_layout: hier gibt es keinen
-- Zeitstempel und keinen Wettlauf zweier Geraete, den man verlieren koennte -
-- zuletzt geschrieben gewinnt, und das ist bei einer Ansichtseinstellung auch
-- die richtige Antwort.
--
-- NULL = noch nie ausgewaehlt. Bewusst kein DEFAULT: so bleibt unterscheidbar,
-- ob jemand 'standard' gewaehlt hat oder nur nie gefragt wurde. Ein spaeterer
-- Wechsel der Voreinstellung wuerde sonst die ausdrueckliche Wahl von
-- Bestandsnutzern ueberschreiben.
alter table public.profiles
  add column if not exists chat_darstellung text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_chat_darstellung_chk'
  ) then
    alter table public.profiles
      add constraint profiles_chat_darstellung_chk
      check (chat_darstellung is null or chat_darstellung in ('standard', 'nachrichten'));
  end if;
end $$;

comment on column public.profiles.chat_darstellung is
  '2026-08-24: Bevorzugte Darstellung des Community-Chats. '
  '''standard'' = Beitragsansicht (heutiges Aussehen), '
  '''nachrichten'' = Messenger-Ansicht mit Sprechblasen. '
  'NULL = noch nie ausgewaehlt, der Client entscheidet dann selbst. Am Konto '
  'und nicht am Geraet, damit die Wahl aufs naechste Handy mitkommt.';
