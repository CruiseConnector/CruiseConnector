-- 2026-08-23 (Auftrag Vucko, Sprachnachricht): „wenn er eine Gruppe erstellt
-- hat und er einen anderen einlaedt und er ueber die Glocke bzw. ueber den
-- Quicklink dann joinen will, dass ein Fehler kommt. [...] wenn nicht, dann
-- umgehend fixen."
--
-- Befund, gemessen in der Produktivdatenbank am 23.08.:
-- Die SELECT-Policy `groups_visible_before_live_or_member` kannte drei Zweige:
-- Ersteller, oeffentlich-und-noch-nicht-gestartet, Mitglied. Einen Zweig fuer
-- Eingeladene gab es nicht. `can_join_group()` dagegen kennt die Einladung
-- ausdruecklich. Ergebnis: BEITRETEN war erlaubt, LESEN nicht. Genau verkehrt
-- herum.
--
-- Der echte Vorfall: Gruppe ac29cf1f-e50f-4b2e-81d3-d99885e7e084 („latenight
-- session", privat, angelegt 21.08. 21:38). Der Eingeladene
-- 645065af-3999-4e66-90cd-c4718c0b8ddf tippte am 21.08. um 21:42:49, 21:42:57
-- und 21:44:13 auf die Glocke. Jedes Mal lieferte
-- GET /rest/v1/groups?select=id&id=eq.ac29cf1f... HTTP 200 mit content_length 2,
-- also eine leere Liste. PostgREST liefert bei RLS-Ausschluss keinen Fehlercode,
-- deshalb hat das Monitoring nie etwas gesehen und der Client hielt die leere
-- Antwort faelschlich fuer „geloescht". Einladungen: 2, eingeloest: 0.
--
-- Nachgerechnet vor dieser Migration (als der Eingeladene, siehe Bericht):
--   groups        -> 0 Zeilen
--   group_members -> 0 Zeilen
-- Nachher: groups -> 1 Zeile, group_members -> 1 Zeile.

-- ---------------------------------------------------------------------------
-- 1. Eine einzige Wahrheit fuer „ist eingeladen"
-- ---------------------------------------------------------------------------
-- Warum eine eigene Funktion statt der Bedingung direkt in der Policy:
-- Genau diese Doppelpflege hat den Defekt erzeugt. Die Einladungsbedingung
-- stand in `can_join_group` und nirgends sonst; als die Lese-Policy spaeter
-- entstand, wurde sie schlicht vergessen. Ab jetzt steht sie an EINER Stelle,
-- und sowohl Lesen als auch Beitreten rufen dieselbe Funktion auf. Wer die
-- Regel kuenftig aendert, aendert beide Wege zwangslaeufig gleichzeitig.
-- SECURITY DEFINER, weil die Policy sonst ueber die RLS von `notifications`
-- stolpern wuerde und weil so kein Rekursionspfad zwischen den Tabellen
-- entsteht.
create or replace function public.ist_zu_gruppe_eingeladen(
  p_group_id uuid,
  p_user_id  uuid
)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select p_user_id is not null
     and p_group_id is not null
     and exists (
       select 1
       from public.notifications n
       where n.user_id = p_user_id
         and n.reference_id = p_group_id
         and n.type = 'group_invite'
     );
$$;

comment on function public.ist_zu_gruppe_eingeladen(uuid, uuid) is
  '2026-08-23: Einzige Wahrheit dafuer, ob jemand zu einer Gruppe eingeladen '
  'ist. Wird von can_join_group() UND von den SELECT-Policies auf groups und '
  'group_members benutzt, damit Lesen und Beitreten nie wieder auseinanderlaufen.';

-- anon behaelt EXECUTE mit Absicht: die SELECT-Policy auf groups wird auch
-- fuer nicht angemeldete Aufrufe geplant, und Postgres prueft das
-- Ausfuehrungsrecht beim Planen, nicht erst wenn der ODER-Zweig drankommt.
-- Ohne Recht gaebe es „permission denied for function" statt einer leeren
-- Liste. Dieselbe Vergabe hat can_join_group seit jeher.
revoke all on function public.ist_zu_gruppe_eingeladen(uuid, uuid) from public;
grant execute on function public.ist_zu_gruppe_eingeladen(uuid, uuid)
  to anon, authenticated, service_role;

-- Hilfsfunktion fuer die Mitgliederliste: Ist die Gruppe noch in der Lobby?
-- Auch SECURITY DEFINER, damit die Policy auf group_members nicht ueber die
-- RLS von groups laufen muss.
create or replace function public.gruppe_ist_in_der_lobby(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1
    from public.groups g
    where g.id = p_group_id
      and coalesce(g.is_active, false) = false
      and g.closed_at is null
  );
$$;

comment on function public.gruppe_ist_in_der_lobby(uuid) is
  '2026-08-23: Gruppe existiert, faehrt noch nicht und ist nicht beendet.';

revoke all on function public.gruppe_ist_in_der_lobby(uuid) from public;
grant execute on function public.gruppe_ist_in_der_lobby(uuid)
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. can_join_group benutzt ab jetzt dieselbe Funktion
-- ---------------------------------------------------------------------------
-- Fachlich unveraendert bis auf EINE bewusste Verschaerfung: `closed_at is
-- null`. `close_group()` setzt closed_at und is_active = false, damit war eine
-- beendete oeffentliche Gruppe bisher wieder beitretbar. Gemessen am 23.08.:
-- 0 Gruppen mit closed_at, also kein Bestandsfall betroffen.
create or replace function public.can_join_group(
  p_group_id uuid,
  p_user_id  uuid
)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select p_user_id is not null
     and exists (
       select 1
       from public.groups g
       where g.id = p_group_id
         and coalesce(g.is_active, false) = false
         and g.closed_at is null
         and (
           coalesce(g.is_public, false) = true
           or public.ist_zu_gruppe_eingeladen(g.id, p_user_id)
         )
     );
$$;

-- ---------------------------------------------------------------------------
-- 3. Die Lese-Policy auf public.groups bekommt den Einladungs-Zweig
-- ---------------------------------------------------------------------------
-- Der Zweig ist bewusst NICHT an `is_active = false` gebunden, obwohl
-- can_join_group das ist. Begruendung: Beitreten waehrend der laufenden Fahrt
-- soll weiterhin gesperrt sein, aber der Eingeladene muss die Gruppe SEHEN
-- koennen, um zu erfahren, dass die Fahrt schon laeuft. Sonst bekaeme er
-- wieder die leere Liste und damit exakt die falsche Meldung „Diese Gruppe ist
-- nicht mehr verfuegbar", die diesen Defekt ausgeloest hat. Lesen ist damit
-- etwas weiter als Beitreten, nie umgekehrt. Die groups-Zeile enthaelt keine
-- Live-Positionen, deshalb ist das unbedenklich.
-- `closed_at is null` begrenzt den Zugang: eine beendete Ausfahrt ist fuer
-- jemanden, der nie beigetreten ist, nicht mehr einsehbar.
drop policy if exists "groups_visible_before_live_or_member" on public.groups;
drop policy if exists "groups_visible_before_live_or_member_or_invited" on public.groups;

create policy "groups_visible_before_live_or_member_or_invited"
on public.groups
for select
using (
  created_by = auth.uid()
  or (coalesce(is_public, false) = true and coalesce(is_active, false) = false)
  or public.is_group_member(id, auth.uid())
  or (closed_at is null and public.ist_zu_gruppe_eingeladen(id, auth.uid()))
);

-- ---------------------------------------------------------------------------
-- 4. Dasselbe fuer public.group_members, aber enger
-- ---------------------------------------------------------------------------
-- Ja, der Eingeladene braucht die Mitgliederliste: der Beitritts-Bildschirm
-- zeigt, wer schon dabei ist, und `max_people` ist ohne die Liste nicht
-- pruefbar (die Gruppe aus dem Vorfall hat max_people = 2).
-- ABER: group_members traegt `current_lat` / `current_lng`, also die
-- Live-Standorte der Mitfahrer. Deshalb ist dieser Zweig zusaetzlich an
-- `gruppe_ist_in_der_lobby()` gebunden. Wer nur eingeladen ist und nicht
-- beitritt, sieht die Liste vor der Abfahrt und ab dem Start nichts mehr.
-- Das entspricht genau dem, was fuer oeffentliche Gruppen schon immer galt.
drop policy if exists "group_members_visible_before_live_or_member" on public.group_members;
drop policy if exists "group_members_visible_before_live_or_member_or_invited" on public.group_members;

create policy "group_members_visible_before_live_or_member_or_invited"
on public.group_members
for select
using (
  exists (
    select 1
    from public.groups g
    where g.id = group_members.group_id
      and coalesce(g.is_public, false) = true
      and coalesce(g.is_active, false) = false
  )
  or public.is_group_member(group_id, auth.uid())
  or (
    public.gruppe_ist_in_der_lobby(group_id)
    and public.ist_zu_gruppe_eingeladen(group_id, auth.uid())
  )
);

-- ---------------------------------------------------------------------------
-- 5. Einladen als RPC, mit Pruefung und mit Gruppenname im payload
-- ---------------------------------------------------------------------------
-- Bisher schrieb der Client die Benachrichtigung selbst und liess `payload`
-- leer (social_service.dart inviteToGroup). Gelesen wird aber
-- payload['group_name'] (notification_service.dart und die Edge send-push),
-- deshalb stand in der Glocke und in der Push-Meldung immer „laedt dich zu
-- einer Gruppe ein" statt des Namens. Beide Einladungen aus dem Vorfall haben
-- payload = {}.
--
-- Warum RPC und nicht Trigger auf notifications: Der Trigger koennte den Namen
-- zwar nachtragen, aber er kann nicht pruefen, WER einlaedt. Und das prueft
-- heute niemand: die INSERT-Policy auf notifications verlangt nur
-- from_user_id = auth.uid(). Jeder angemeldete Nutzer konnte also eine
-- „Einladung" zu einer fremden Gruppe verschicken, und mit dem neuen
-- Lese-Zweig oben wuerde er sich damit selbst Zugang zu einer privaten Gruppe
-- verschaffen. Die RPC schliesst dieses Loch mit, indem sie
-- is_group_owner() verlangt.
create or replace function public.invite_to_group(
  p_group_id uuid,
  p_user_id  uuid
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_host            uuid := auth.uid();
  v_group           public.groups%rowtype;
  v_notification_id uuid;
begin
  if v_host is null then
    raise exception 'Bitte melde dich an.';
  end if;

  if p_user_id is null or p_user_id = v_host then
    raise exception 'Du kannst dich nicht selbst einladen.';
  end if;

  select * into v_group from public.groups where id = p_group_id;
  if not found then
    raise exception 'Diese Gruppe gibt es nicht mehr.';
  end if;

  -- Gastgeber ODER Mitglied. Bewusst nicht nur der Gastgeber, obwohl der
  -- Auftrag das nahelegte: der Einladen-Knopf in der Lobby
  -- (group_lobby_page.dart:689) ist heute an KEINE Rolle gebunden, jedes
  -- Mitglied kann einladen, und Mitglieder duerfen ohnehin schon den
  -- Einladungscode und den Teilen-Link weitergeben. Owner-only wuerde diesen
  -- Weg still zerbrechen, sobald der Client auf die RPC umgestellt wird.
  -- Zugemacht wird das, was wirklich offen war: Wer weder Gastgeber noch
  -- Mitglied ist, kann jetzt niemanden mehr in eine fremde private Gruppe
  -- einladen. Soll es doch nur der Gastgeber sein, muss zuerst der Knopf in
  -- der Lobby an _hasOwnerPower gebunden werden.
  if not (
    public.is_group_owner(p_group_id, v_host)
    or public.is_group_member(p_group_id, v_host)
  ) then
    raise exception 'Nur wer selbst in der Gruppe ist, darf einladen.';
  end if;

  if v_group.closed_at is not null then
    raise exception 'Diese Ausfahrt ist schon beendet.';
  end if;

  if coalesce(v_group.is_active, false) = true then
    raise exception 'Die Fahrt läuft bereits, jetzt kann niemand mehr dazukommen.';
  end if;

  -- Schon dabei: keine Einladung noetig, aber auch kein Fehler.
  if public.is_group_member(p_group_id, p_user_id) then
    return null;
  end if;

  if public.is_blocked_pair(p_user_id, v_host) then
    raise exception 'Diese Person kannst du nicht einladen.';
  end if;

  -- Aeltere Einladung desselben Paares raeumen. Im Vorfall lagen zwei
  -- identische Zeilen fuer dieselbe Gruppe in der Glocke.
  delete from public.notifications
   where user_id = p_user_id
     and reference_id = p_group_id
     and type = 'group_invite';

  insert into public.notifications (user_id, from_user_id, type, reference_id, payload)
  values (
    p_user_id,
    v_host,
    'group_invite',
    p_group_id,
    jsonb_build_object(
      'action', 'group_invite',
      'group_id', p_group_id::text,
      'group_name', coalesce(nullif(v_group.name, ''), 'Gruppe')
    )
  )
  returning id into v_notification_id;

  return v_notification_id;
end;
$$;

comment on function public.invite_to_group(uuid, uuid) is
  '2026-08-23: Einladung zu einer Gruppe. Prueft, ob der Aufrufer Gastgeber '
  'ist, und schreibt den Gruppennamen in payload.group_name.';

-- Supabase vergibt EXECUTE beim CREATE per Default-Privileg auch an `anon`.
-- Ein `revoke ... from public` erwischt das NICHT, deshalb hier ausdruecklich.
-- Vom Advisor am 23.08. bestaetigt: ohne diese Zeile taucht die Funktion als
-- `anon_security_definer_function_executable` auf.
revoke all on function public.invite_to_group(uuid, uuid) from public, anon;
grant execute on function public.invite_to_group(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Die Gegenrichtung: Einladung zuruecknehmen
-- ---------------------------------------------------------------------------
-- Ohne diese Funktion waere die Einladung eine Einbahnstrasse. Die
-- DELETE-Policy auf notifications erlaubt nur `auth.uid() = user_id`, also
-- kann heute NUR der Eingeladene seine eigene Einladung loeschen, der
-- Gastgeber nicht. Mit dem neuen Lese-Zweig haette der Gastgeber damit keine
-- Moeglichkeit, den Zugang wieder zu entziehen.
--
-- Verhalten des Zugangs, ausdruecklich festgehalten:
--  * Einladung zurueckgezogen (diese RPC) oder vom Empfaenger geloescht
--    -> `ist_zu_gruppe_eingeladen` wird false, die Gruppe verschwindet sofort
--       wieder aus seiner Sicht. Der Zugang haengt an der Benachrichtigung,
--       nicht an einem Zeitstempel.
--  * Gruppe geschlossen (`close_group` setzt closed_at)
--    -> Lese-Zweig und can_join_group fallen weg. Mitglieder behalten ihren
--       Zugang ueber `is_group_member` (Rangliste, Chat, Rejoin).
--  * Gruppe geloescht -> der Trigger `trg_cleanup_notifs_groups` raeumt die
--    Benachrichtigungen mit weg, es bleibt nichts zurueck.
--  * Fahrt gestartet -> Beitreten gesperrt, Mitgliederliste unsichtbar,
--    die Gruppenzeile bleibt lesbar (siehe Begruendung in Abschnitt 3).
--  * Bereits beigetreten und danach Einladung zurueckgezogen -> die
--    Mitgliedschaft bleibt. Wer jemanden loswerden will, entfernt ihn ueber
--    „Owner kann Mitglieder entfernen". Eine Einladung zurueckziehen ist
--    ausdruecklich KEIN Rauswurf.
create or replace function public.revoke_group_invite(
  p_group_id uuid,
  p_user_id  uuid
)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_host  uuid := auth.uid();
  v_count integer;
begin
  if v_host is null then
    raise exception 'Bitte melde dich an.';
  end if;

  if not public.is_group_owner(p_group_id, v_host) then
    raise exception 'Nur der Gastgeber darf Einladungen zurücknehmen.';
  end if;

  with weg as (
    delete from public.notifications
     where user_id = p_user_id
       and reference_id = p_group_id
       and type = 'group_invite'
    returning 1
  )
  select count(*)::integer into v_count from weg;

  return v_count;
end;
$$;

comment on function public.revoke_group_invite(uuid, uuid) is
  '2026-08-23: Gastgeber nimmt eine Gruppeneinladung zurueck. Entzieht damit '
  'auch den Lesezugang, entfernt aber niemanden, der schon beigetreten ist.';

revoke all on function public.revoke_group_invite(uuid, uuid) from public, anon;
grant execute on function public.revoke_group_invite(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Bestand nachziehen: Gruppenname in alte Einladungen eintragen
-- ---------------------------------------------------------------------------
-- Betrifft die beiden Zeilen aus dem Vorfall. Ohne das steht in der Glocke
-- des Fahrers bis heute „laedt dich zu einer Gruppe ein".
update public.notifications n
   set payload = coalesce(n.payload, '{}'::jsonb)
                 || jsonb_build_object(
                      'action', 'group_invite',
                      'group_id', g.id::text,
                      'group_name', coalesce(nullif(g.name, ''), 'Gruppe')
                    )
  from public.groups g
 where n.reference_id = g.id
   and n.type = 'group_invite'
   and coalesce(n.payload -> 'group_name', 'null'::jsonb) = 'null'::jsonb;
