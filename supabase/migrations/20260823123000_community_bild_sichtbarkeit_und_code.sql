-- ═══════════════════════════════════════════════════════════════════════════
-- Communities: Profilbild, dichter Privat-Schalter, geschuetzter Einladungscode
--
-- Auftrag Vucko 2026-08-23 (Sprachnachricht, woertlich):
--   „...dass man fuer Communities wirklich auch Profilbilder reintun kann und
--   auch entweder in den nur Schreibmodus fuer den Admin einstellen kann oder
--   auch Schreibmodus fuer alle. Und ganz wichtig, dass man auch im Nachhinein
--   einstellen kann, ob eine Community privat oder oeffentlich ist."
--
-- Entscheidung Vucko vom 23.08.2026 (bindend):
--   „Wechselt eine Community von oeffentlich auf privat, fuehrt ein alter,
--   schon geteilter Link NICHT mehr direkt hinein, sondern loest eine
--   BEITRITTSANFRAGE beim Admin aus, die er annehmen oder ablehnen kann.
--   Bestehende Mitglieder behalten ihren Zugang."
--
-- GEMESSENER IST-ZUSTAND, der diese Migration ausgeloest hat:
--   1. public.communities hatte genau 9 Spalten, kein Bildfeld, keinen Bucket.
--      Buckets am 23.08.2026: banners, avatars, car_images, ride-photos,
--      feedback. Fuer Communities gab es nichts.
--   2. join_community_with_code (SECURITY DEFINER) las is_public an KEINER
--      Stelle und trug direkt in community_members ein. Der Privat-Schalter
--      war damit wertlos: Code einmal abgreifen, spaeter nach dem Wechsel
--      auf privat damit eintreten.
--   3. Jeder angemeldete Nutzer konnte den invite_code JEDER oeffentlichen
--      Community lesen: die Zeilenregel communities_visible_public_or_member
--      gibt oeffentliche Zeilen frei, und `authenticated` hatte ein
--      TABELLENWEITES select-Recht (pg_class.relacl = authenticated=arwdDxtm).
--      Codes liessen sich also auf Vorrat sammeln.
--   4. Auf communities lagen ZWEI After-Insert-Trigger mit derselben Aufgabe.
--
-- BELEG, dass die beiden Trigger dasselbe tun (pg_get_triggerdef +
-- pg_get_functiondef am 23.08.2026 abgefragt):
--   trg_add_community_owner    AFTER INSERT ... EXECUTE add_community_owner_as_member()
--       -> if new.owner_id is not null then
--            insert into community_members (community_id, user_id, role)
--            values (new.id, new.owner_id, 'owner')
--            on conflict (community_id, user_id) do nothing;
--   trg_community_owner_member AFTER INSERT ... EXECUTE set_community_owner_member_on_insert()
--       -> insert into community_members (community_id, user_id, role)
--          values (new.id, new.owner_id, 'owner')
--          on conflict (community_id, user_id) do update set role = 'owner';
--   Gleiche Tabelle, gleiches Ereignis, gleiche Zeile, gleiche Werte. Der
--   Null-Test im ersten ist toter Code, weil communities.owner_id NOT NULL ist
--   (information_schema.columns: is_nullable = NO). Einziger Unterschied:
--   do-nothing gegen do-update. Der zweite ist der staerkere und bleibt.
-- ═══════════════════════════════════════════════════════════════════════════


-- ───────────────────────────────────────────────────────────────────────────
-- 1. Profilbild-Spalte
--
-- Die bestehende Update-Regel deckt sie OHNE Aenderung ab: RLS-Regeln gelten
-- pro ZEILE, nicht pro Spalte. leaders_update_communities lautet
-- USING is_community_admin(id, auth.uid()) / WITH CHECK dasselbe und trifft
-- damit jede Spalte derselben Zeile, auch neue. Das Tabellenrecht war
-- ebenfalls tabellenweit (relacl authenticated=arwdDxtm), eine neue Spalte
-- erbt es automatisch. Es braucht also keine zweite Update-Regel.
-- ───────────────────────────────────────────────────────────────────────────

alter table public.communities
  add column if not exists avatar_url text;

comment on column public.communities.avatar_url is
  'Oeffentliche URL des Community-Bildes im Bucket community_images. '
  'Geschrieben ueber leaders_update_communities, also von jedem Admin.';


-- ───────────────────────────────────────────────────────────────────────────
-- 2. Bucket fuer Community-Bilder
--
-- Warum NICHT der uebliche Nutzer-Ordner: is_community_admin prueft die ROLLE
-- in community_members, nicht communities.owner_id. Gemessen: „Has.Crew" hat
-- 2 Zeilen mit role = 'owner'. Alle bestehenden Storage-Regeln verlangen aber
-- (auth.uid())::text = (storage.foldername(name))[1]. Damit koennte Admin B
-- das Bild von Admin A nie ersetzen. Der Ordner ist deshalb die
-- COMMUNITY-Kennung, und die Regel fragt is_community_admin.
--
-- Die Ordner-Kennung wird ueber safe_uuid gelesen: ein direktes
-- (storage.foldername(name))[1]::uuid wirft 22P02, sobald irgendjemand einen
-- Ordner anlegt, der keine UUID ist. In einer USING-Bedingung wuerde dieser
-- Fehler die ganze Abfrage abbrechen, nicht nur diese eine Zeile.
-- ───────────────────────────────────────────────────────────────────────────

create or replace function public.safe_uuid(p_text text)
returns uuid
language plpgsql
immutable
set search_path to 'public', 'pg_temp'
as $function$
begin
  return p_text::uuid;
exception when others then
  return null;
end;
$function$;

comment on function public.safe_uuid(text) is
  'Wandelt Text in eine UUID um und liefert NULL statt eines Fehlers, wenn '
  'der Text keine UUID ist. Fuer Storage-Regeln, die Ordnernamen auswerten.';

grant execute on function public.safe_uuid(text) to anon, authenticated;

-- Groesse und Dateitypen wie beim feedback-Bucket (5 MiB, jpeg/png/webp).
-- Anders als feedback ist der Bucket OEFFENTLICH lesbar: das Bild haengt an
-- jeder Community-Kachel und soll wie avatars und banners ueber eine
-- dauerhafte URL geladen werden koennen.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'community_images',
  'community_images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
  set public = true,
      file_size_limit = 5242880,
      allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists "community_images_lesen" on storage.objects;
create policy "community_images_lesen" on storage.objects
  for select to authenticated
  using (bucket_id = 'community_images');

drop policy if exists "community_images_hochladen_admin" on storage.objects;
create policy "community_images_hochladen_admin" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'community_images'
    and public.is_community_admin(
      public.safe_uuid((storage.foldername(name))[1]),
      (select auth.uid())
    )
  );

drop policy if exists "community_images_ersetzen_admin" on storage.objects;
create policy "community_images_ersetzen_admin" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'community_images'
    and public.is_community_admin(
      public.safe_uuid((storage.foldername(name))[1]),
      (select auth.uid())
    )
  )
  with check (
    bucket_id = 'community_images'
    and public.is_community_admin(
      public.safe_uuid((storage.foldername(name))[1]),
      (select auth.uid())
    )
  );

drop policy if exists "community_images_loeschen_admin" on storage.objects;
create policy "community_images_loeschen_admin" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'community_images'
    and public.is_community_admin(
      public.safe_uuid((storage.foldername(name))[1]),
      (select auth.uid())
    )
  );


-- ───────────────────────────────────────────────────────────────────────────
-- 3. Der Privat-Schalter wird dicht
--
-- Neu: join_community_with_code_v2 liefert jsonb und sagt der App, WAS
-- passiert ist, damit sie den richtigen Text zeigt.
--   status = 'joined'           -> „Willkommen"
--   status = 'already_member'   -> war schon drin
--   status = 'request_created'  -> „Deine Anfrage ist beim Admin"
--   status = 'request_pending'  -> Anfrage lag schon offen, keine zweite
--   status = 'request_rejected' -> vor kurzem abgelehnt, Sperrfrist laeuft
--
-- Der Sonderfall „zehn Anfragen hintereinander" ist doppelt abgesichert:
-- community_join_requests hat UNIQUE (community_id, user_id), und die Funktion
-- liest die vorhandene Zeile vorher mit FOR UPDATE. Eine abgelehnte Anfrage
-- darf erst nach 7 Tagen erneut gestellt werden, sonst koennte man den Admin
-- durch Ablehnen-und-sofort-neu-Fragen zumuellen.
-- ───────────────────────────────────────────────────────────────────────────

create or replace function public.join_community_with_code_v2(p_code text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_code      text;
  v_community public.communities%rowtype;
  v_uid       uuid;
  v_request   public.community_join_requests%rowtype;
  v_antwort   jsonb;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Bitte melde dich an.';
  end if;

  v_code := public.normalize_community_invite_code(p_code);
  if v_code is null then
    raise exception 'Code ungültig.';
  end if;

  select * into v_community
  from public.communities
  where upper(invite_code) = upper(v_code);

  if not found then
    raise exception 'Code ungültig.';
  end if;

  v_antwort := jsonb_build_object(
    'community_id', v_community.id,
    'name', v_community.name,
    'is_public', coalesce(v_community.is_public, false)
  );

  -- Bestehende Mitglieder behalten ihren Zugang, auch nach dem Wechsel
  -- auf privat. Ausdrueckliche Entscheidung Vuckos vom 23.08.2026.
  if public.is_community_member(v_community.id, v_uid) then
    return v_antwort || jsonb_build_object('status', 'already_member');
  end if;

  if coalesce(v_community.is_public, false) then
    insert into public.community_members (community_id, user_id, role)
    values (v_community.id, v_uid, 'member')
    on conflict (community_id, user_id) do nothing;
    return v_antwort || jsonb_build_object('status', 'joined');
  end if;

  -- Ab hier: privat. Der Code fuehrt NICHT mehr hinein, er fragt an.
  select * into v_request
  from public.community_join_requests
  where community_id = v_community.id
    and user_id = v_uid
  for update;

  if found then
    if v_request.status = 'pending' then
      return v_antwort || jsonb_build_object(
        'status', 'request_pending',
        'request_id', v_request.id
      );
    end if;

    if v_request.status = 'rejected'
       and coalesce(v_request.responded_at, v_request.created_at)
           > now() - interval '7 days' then
      return v_antwort || jsonb_build_object(
        'status', 'request_rejected',
        'request_id', v_request.id
      );
    end if;

    -- Alte abgelehnte oder alte angenommene Zeile (Mitglied ist inzwischen
    -- ausgetreten oder entfernt worden) wird zur frischen Anfrage.
    update public.community_join_requests
       set status = 'pending',
           message = null,
           created_at = now(),
           responded_at = null
     where id = v_request.id;

    return v_antwort || jsonb_build_object(
      'status', 'request_created',
      'request_id', v_request.id
    );
  end if;

  begin
    insert into public.community_join_requests (community_id, user_id, status)
    values (v_community.id, v_uid, 'pending')
    returning * into v_request;
  exception when unique_violation then
    -- Zwei Klicks gleichzeitig: die andere Sitzung war schneller.
    select * into v_request
    from public.community_join_requests
    where community_id = v_community.id
      and user_id = v_uid;
    return v_antwort || jsonb_build_object(
      'status', 'request_pending',
      'request_id', v_request.id
    );
  end;

  return v_antwort || jsonb_build_object(
    'status', 'request_created',
    'request_id', v_request.id
  );
end;
$function$;

comment on function public.join_community_with_code_v2(text) is
  'Beitritt per Einladungscode. Oeffentlich = sofort Mitglied, privat = '
  'Beitrittsanfrage beim Admin. Entscheidung Vucko 23.08.2026.';

revoke all on function public.join_community_with_code_v2(text) from public, anon;
grant execute on function public.join_community_with_code_v2(text) to authenticated;

-- Der alte Weg bleibt bestehen (Rueckgabetyp uuid), weil alte App-Fassungen
-- installiert bleiben und `result as String` auswerten. Ein jsonb-Rueckgabewert
-- wuerde dort in einen Cast-Fehler laufen. Geaendert wird nur das Loch:
-- eine PRIVATE Community laesst er nicht mehr durch. Er legt hier bewusst
-- KEINE Anfrage an, denn `raise exception` wuerde sie im selben Rollback
-- wieder mitnehmen. Die alte App bekommt stattdessen einen klaren Satz.
create or replace function public.join_community_with_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_code      text;
  v_community public.communities%rowtype;
  v_uid       uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Bitte melde dich an.';
  end if;

  v_code := public.normalize_community_invite_code(p_code);
  if v_code is null then
    raise exception 'Code ungültig.';
  end if;

  select * into v_community
  from public.communities
  where upper(invite_code) = upper(v_code);

  if not found then
    raise exception 'Code ungültig.';
  end if;

  if public.is_community_member(v_community.id, v_uid) then
    return v_community.id;
  end if;

  if not coalesce(v_community.is_public, false) then
    raise exception 'Diese Community ist privat. Bitte aktualisiere die App, dann kannst du eine Beitrittsanfrage stellen.';
  end if;

  insert into public.community_members (community_id, user_id, role)
  values (v_community.id, v_uid, 'member')
  on conflict (community_id, user_id) do nothing;

  return v_community.id;
end;
$function$;

comment on function public.join_community_with_code(text) is
  'Alter Beitrittsweg fuer bereits installierte App-Fassungen. Laesst seit '
  '23.08.2026 keine private Community mehr durch. Neu: '
  'join_community_with_code_v2.';

-- Annehmen und Ablehnen gab es schon (accept_community_join_request /
-- reject_community_join_request, beide SECURITY DEFINER, beide pruefen
-- is_community_owner). Sie bleiben unveraendert und passen zum neuen Weg.
-- Neu ist nur die Liste der offenen Anfragen fuer den Admin, damit die App
-- nicht ueber die Tabelle selbst gehen muss.
create or replace function public.get_community_join_requests(p_community_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_liste jsonb;
begin
  if v_uid is null then
    raise exception 'Bitte melde dich an.';
  end if;

  if not public.is_community_owner(p_community_id, v_uid) then
    raise exception 'Nur Admins sehen die Beitrittsanfragen.';
  end if;

  select coalesce(jsonb_agg(zeile order by zeile->>'created_at' desc), '[]'::jsonb)
  into v_liste
  from (
    select jsonb_build_object(
      'id', r.id,
      'user_id', r.user_id,
      'status', r.status,
      'message', r.message,
      'created_at', r.created_at,
      'profile', jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'avatar_url', p.avatar_url
      )
    ) as zeile
    from public.community_join_requests r
    left join public.profiles p on p.id = r.user_id
    where r.community_id = p_community_id
      and r.status = 'pending'
  ) t;

  return v_liste;
end;
$function$;

revoke all on function public.get_community_join_requests(uuid) from public, anon;
grant execute on function public.get_community_join_requests(uuid) to authenticated;


-- ───────────────────────────────────────────────────────────────────────────
-- 4. Der Einladungscode ist nicht mehr abgreifbar
--
-- Zeilenregeln reichen hier nicht: die Zeile einer oeffentlichen Community
-- SOLL sichtbar sein, nur eine einzige Spalte darin nicht. Also wird das
-- tabellenweite select-Recht durch eine Spaltenliste ohne invite_code
-- ersetzt. insert und update auf invite_code fallen gleich mit weg, damit
-- sich niemand einen selbst gewaehlten Code setzen kann; den Code vergibt
-- weiterhin allein der Trigger trg_community_defaults.
--
-- ACHTUNG fuer spaeter: ab jetzt ist das Leserecht spaltenweise. JEDE neue
-- Spalte auf public.communities braucht ein eigenes `grant select (spalte)`,
-- sonst sieht die App sie nicht.
-- ───────────────────────────────────────────────────────────────────────────

revoke select, insert, update on public.communities from anon, authenticated;

grant select (
  id, owner_id, name, description, is_public,
  created_at, updated_at, owner_only_messages, avatar_url
) on public.communities to anon, authenticated;

grant insert (
  id, owner_id, name, description, is_public,
  created_at, updated_at, owner_only_messages, avatar_url
) on public.communities to anon, authenticated;

grant update (
  name, description, is_public, updated_at, owner_only_messages, avatar_url
) on public.communities to anon, authenticated;

-- Der eigene Code kommt ab jetzt hierueber. Mitglieder duerfen ihn holen,
-- weil genau sie damit Freunde einladen sollen. Nicht-Mitglieder nicht.
create or replace function public.get_community_invite_code(p_community_id uuid)
returns text
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_uid  uuid := auth.uid();
  v_code text;
begin
  if v_uid is null then
    raise exception 'Bitte melde dich an.';
  end if;

  if not public.is_community_member(p_community_id, v_uid) then
    raise exception 'Nur Mitglieder sehen den Einladungscode.';
  end if;

  select invite_code into v_code
  from public.communities
  where id = p_community_id;

  return v_code;
end;
$function$;

comment on function public.get_community_invite_code(uuid) is
  'Liefert den Einladungscode NUR an Mitglieder. Ersetzt das offene Lesen '
  'der Spalte communities.invite_code (Leck gemessen am 23.08.2026).';

revoke all on function public.get_community_invite_code(uuid) from public, anon;
grant execute on function public.get_community_invite_code(uuid) to authenticated;


-- ───────────────────────────────────────────────────────────────────────────
-- 5. Suche per Code liefert Bild und Schreibmodus mit
--
-- find_community_by_code braucht den Code als EINGABE und bleibt deshalb
-- unveraendert benutzbar. Sie ist SECURITY DEFINER und laeuft an den neuen
-- Spaltenrechten vorbei, was hier richtig ist: wer den Code schon kennt,
-- darf das Ergebnis sehen. Neu im Ergebnis: avatar_url (Bild) und
-- owner_only_messages (fehlte bisher schon).
-- ───────────────────────────────────────────────────────────────────────────

create or replace function public.find_community_by_code(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_code text;
  v_community public.communities%rowtype;
  v_member_count integer;
  v_owner jsonb;
begin
  v_code := public.normalize_community_invite_code(p_code);
  if v_code is null then
    return null;
  end if;

  select * into v_community
  from public.communities
  where upper(invite_code) = upper(v_code);

  if not found then
    return null;
  end if;

  select count(*) into v_member_count
  from public.community_members cm
  where cm.community_id = v_community.id;

  select jsonb_build_object(
    'id', p.id,
    'username', p.username,
    'avatar_url', p.avatar_url
  )
  into v_owner
  from public.profiles p
  where p.id = v_community.owner_id;

  return jsonb_build_object(
    'id', v_community.id,
    'owner_id', v_community.owner_id,
    'name', v_community.name,
    'description', v_community.description,
    'is_public', v_community.is_public,
    'owner_only_messages', v_community.owner_only_messages,
    'avatar_url', v_community.avatar_url,
    'invite_code', v_code,
    'created_at', v_community.created_at,
    'member_count', v_member_count,
    'owner_profile', v_owner
  );
end;
$function$;


-- ───────────────────────────────────────────────────────────────────────────
-- 6. Aufraeumen: der schwaechere der beiden Doppel-Trigger fliegt raus
--    (Beleg der Gleichheit steht oben im Kopf dieser Datei)
-- ───────────────────────────────────────────────────────────────────────────

drop trigger if exists trg_add_community_owner on public.communities;
drop function if exists public.add_community_owner_as_member();
