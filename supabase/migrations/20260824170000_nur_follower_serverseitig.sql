-- 2026-08-24 (vucko): "bei der community page hat cozy mal was gepostet aber
-- ich sehe es nicht in meinem feed obwohl ich ihm folge."
--
-- BEFUND
-- ------
-- Zwei Fehler lagen uebereinander:
--
-- 1. Der Client (social_service.dart, getFeedPosts) holte Beitraege mit
--    visibility = 'followers' nur von Leuten, die ZURUECKFOLGEN. Vucko folgt
--    cozy, cozy folgt nicht zurueck -> cozys zwei Beitraege vom 21.08. fielen
--    aus dem Feed. Die Beschriftung im Beitragsdialog heisst aber schlicht
--    "Follower" (create_post_page.dart), nicht "gegenseitig". Der Client wird
--    in einer eigenen Aenderung geradegezogen.
--
-- 2. Die Leseregel auf `posts` lautete `qual = true`. Jeder angemeldete Nutzer
--    durfte JEDEN Beitrag lesen, auch die auf "Nur Follower" gestellten. Die
--    Einschraenkung existierte AUSSCHLIESSLICH in der Client-Abfrage. Wer die
--    Schnittstelle direkt anspricht, las alles. Genau das raeumt diese
--    Migration auf: die Einstellung bedeutet ab jetzt serverseitig etwas.
--
-- DIE REGEL
-- ---------
--   * eigene Beitraege        -> immer
--   * visibility = 'public'   -> fuer jeden angemeldeten Nutzer
--   * visibility = 'followers'-> fuer jeden, der dem Verfasser FOLGT
--                                (einseitig genuegt, so wie die Beschriftung
--                                es verspricht)
--   * Blockierung in eine der beiden Richtungen sticht alles.
--     Dafuer wird `is_blocked_pair` benutzt, dieselbe Funktion, die schon
--     `profiles`, `follows` und `notifications` benutzen. Kein zweites Muster.
--   * Moderation (`is_admin()`) sieht weiterhin alles.
--
--     Nachgemessen, damit hier keine Legende steht: die Moderationswege
--     brauchen diesen Zweig heute NICHT. `v_admin_reports_inbox` ist zwar
--     security_invoker und haengt `posts` per LEFT JOIN an, aber
--     `authenticated` wurde das Leserecht darauf am 26.06. bewusst
--     entzogen — sie laeuft ueber `service_role`, und die hat BYPASSRLS.
--     `admin_delete_post`, `admin_ban_user` und das gesamte
--     admin_monitor_* sind SECURITY DEFINER. Keiner dieser Wege beruehrt
--     die neue Regel.
--
--     Der Zweig bleibt trotzdem drin, als Reserve fuer Moderation, die als
--     angemeldeter Admin laeuft. Er kostet nichts: `(select ...)` macht
--     daraus einen InitPlan, der einmal pro Abfrage laeuft, nicht pro
--     Zeile. Und er legt nichts offen, was ein Admin nicht ohnehin ueber
--     service_role saehe.
--
-- MITGEZOGEN
-- ----------
-- Kommentare, Likes, Reposts und Hashtag-Zeilen haengen an einem Beitrag. Sie
-- standen bisher ebenfalls auf `qual = true`, d. h. der Kommentartext unter
-- einem "Nur Follower"-Beitrag war fuer jeden lesbar. Sie erben ab jetzt die
-- Sichtbarkeit ihres Beitrags ueber ein `exists (... from public.posts ...)`.
-- Die Regel steht damit an genau EINER Stelle; die Unterabfrage laeuft im
-- Kontext des Aufrufers, die neue posts-Regel greift also mit.
--
-- Auch die Schreibseite: liken, kommentieren und reposten geht nur noch auf
-- einen Beitrag, den man auch sehen darf. Sonst kann ein Fremder die Zaehler
-- eines privaten Beitrags hochtreiben und dem Verfasser Benachrichtigungen
-- schicken, ohne den Beitrag je gesehen zu haben.
--
-- DIE ZAEHLER
-- -----------
-- `likes_count`, `comments_count` und `reposts_count` stehen als Spalte auf
-- `posts` und wurden von sechs SECURITY-DEFINER-Funktionen blind um 1 hoch-
-- oder heruntergezaehlt. Zwei Gruende, das jetzt mitzunehmen:
--
--   1. Der Client hat einen Rueckfallweg: schlaegt `toggle_post_like` fehl,
--      versucht er den Einfuege-Weg und ruft danach `increment_likes`
--      (social_service.dart, toggleLikeWithCount). Genau diesen Rueckfall
--      loest die neue Ablehnung aus. Der Einfuegeversuch scheitert jetzt an
--      der Regel — aber `increment_likes` selbst fragt nichts und wuerde die
--      Zahl trotzdem hochzaehlen. Dann zeigt eine Zahl ins Leere.
--   2. `+ 1` ist keine Wahrheit, sondern eine Behauptung. Die Funktionen
--      zaehlen ab jetzt aus der Quelle nach. Damit kann kein Fremder eine
--      Zahl hochtreiben, und die Zahl kann nicht von den sichtbaren Zeilen
--      abweichen: sie IST deren Anzahl.
--
-- Die sechs hatten ausserdem kein `search_path` gesetzt. Das ist hier
-- miterledigt.
--
-- DER HINWEISPUNKT
-- ----------------
-- `community_hinweispunkte` traegt denselben Denkfehler ein zweites Mal: der
-- Zaehler am Feed-Reiter verlangte fuer "Nur Follower" ebenfalls, dass der
-- Verfasser ZURUECKFOLGT. Die Funktion ist SECURITY DEFINER, die neue
-- Leseregel erreicht sie also nicht. Ohne diese Korrektur bliebe der Punkt
-- blind fuer genau die Beitraege, die ab jetzt im Feed stehen — cozys zwei
-- waeren sichtbar, aber der Punkt haette sie nicht gezaehlt.
--
-- LEISTUNG (gemessen am 24.08.2026, nicht geschaetzt)
-- --------------------------------------------------
-- `beitrag_lesbar` laeuft je Zeile, die die Regel passieren muss.
-- EXPLAIN ANALYZE auf dem Feed-Muster (`order by created_at desc limit 80`):
-- rund 0,2 ms pro gepruefter Zeile. `is_admin()` steht als `(select ...)` da
-- und laeuft als InitPlan EINMAL pro Abfrage (im Plan: loops=1), nicht je
-- Zeile — das ist der Unterschied zwischen 1 und 80 Aufrufen.
--
-- Hochgerechnet:
--   Feed, 80 Zeilen ........................ ~16 ms   unkritisch
--   fremdes Profil, 500 Beitraege .......... ~100 ms  spuerbar
--   ungefiltertes count(*) ueber 100.000 ... ~20 s    unbrauchbar
--
-- Die App stellt die dritte Art Abfrage nicht: das Monitoring zaehlt ueber
-- admin_monitor_* (SECURITY DEFINER), die an der Regel vorbeilaeuft. Wenn
-- die Beitragszahl irgendwann fuenfstellig wird, ist die Stelle, die zuerst
-- weh tut, das Profil eines Vielposters.
--
-- FEHLT EIN INDEX? Nein, nachgesehen: die Folge-Pruefung trifft
-- `idx_follows_follower_following` (unique, ein Punkt-Lookup), die
-- Blockierpruefung den Primaerschluessel von `user_blocks`. Die Kosten sind
-- der Funktionsaufruf selbst, nicht ein fehlender Index. Gegengeprobt:
-- dieselbe Funktion OHNE `security definer` gebaut und gemessen — kein
-- Unterschied (429 us gegen 429 us). Der Kontextwechsel ist es also auch
-- nicht; der groesste Einzelposten ist `is_blocked_pair` mit ~180 us.
--
-- NICHT angefasst (bewusst, siehe Bericht):
--   * `is_hidden` bleibt eine reine Client-Filterung.
--   * `profiles.is_private` gilt weiter nicht fuer oeffentliche Beitraege.
--   * `hashtag_beitraege` zeigt weiterhin Beitraege blockierter Personen —
--     ein eigener, aelterer Mangel, der nichts mit "Nur Follower" zu tun hat.

-- WIEDERHOLBAR
-- ------------
-- Jede neue Regel wird vor dem Anlegen zuerst weggeworfen (`drop policy if
-- exists` auf BEIDE Namen, den alten und den neuen). Grund: angewandt wurde
-- ueber den Supabase-MCP, und der vergibt einen eigenen Zeitstempel — hier
-- 20260824163500 statt 20260824170000. Der Eintrag in
-- `supabase_migrations.schema_migrations` wurde auf den Dateinamen
-- geradegezogen; sollte die Datei trotzdem noch einmal laufen, scheitert sie
-- jetzt nicht an "policy already exists".

-- ---------------------------------------------------------------------------
-- 1. Die Regel als Funktion. Eine Quelle, mehrere Nutzer.
-- ---------------------------------------------------------------------------

create or replace function public.beitrag_lesbar(
  p_autor      uuid,
  p_visibility text
) returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select case
    -- Nicht angemeldet: nichts. `profiles` haelt es genauso.
    when (select auth.uid()) is null              then false
    when p_autor is null                          then false
    -- Der eigene Beitrag ist immer lesbar, auch "Nur Follower".
    when p_autor = (select auth.uid())            then true
    -- Blockierung in eine der beiden Richtungen sticht alles.
    when public.is_blocked_pair(p_autor, (select auth.uid())) then false
    -- Altbestand ohne gesetzte Sichtbarkeit gilt als oeffentlich.
    when coalesce(p_visibility, 'public') = 'public' then true
    when p_visibility = 'followers' then exists (
      select 1
        from public.follows f
       where f.follower_id  = (select auth.uid())
         and f.following_id = p_autor
         and f.status       = 'accepted'
    )
    -- Unbekannte Sichtbarkeit ist im Zweifel privat.
    else false
  end;
$$;

comment on function public.beitrag_lesbar(uuid, text) is
  'Darf der angemeldete Nutzer einen Beitrag dieses Verfassers mit dieser '
  'Sichtbarkeit lesen? "followers" heisst einseitig folgen, nicht '
  'gegenseitig. Blockierung in beide Richtungen sticht.';

revoke execute on function public.beitrag_lesbar(uuid, text) from public;
revoke execute on function public.beitrag_lesbar(uuid, text) from anon;
grant  execute on function public.beitrag_lesbar(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. posts: die eigentliche Leseregel.
-- ---------------------------------------------------------------------------

drop policy if exists "Posts sind öffentlich lesbar" on public.posts;

drop policy if exists "Beitraege nach Sichtbarkeit lesbar" on public.posts;

create policy "Beitraege nach Sichtbarkeit lesbar"
  on public.posts
  for select
  to authenticated
  using (
    -- `(select ...)` macht daraus einen InitPlan: einmal pro Abfrage statt
    -- einmal pro Zeile.
    (select public.is_admin())
    or public.beitrag_lesbar(user_id, visibility)
  );

-- ---------------------------------------------------------------------------
-- 3. Was am Beitrag haengt, erbt dessen Sichtbarkeit.
-- ---------------------------------------------------------------------------

-- Kommentare -----------------------------------------------------------------
drop policy if exists "Comments sind öffentlich lesbar" on public.comments;

drop policy if exists "Kommentare nur zu sichtbaren Beitraegen" on public.comments;

create policy "Kommentare nur zu sichtbaren Beitraegen"
  on public.comments
  for select
  to authenticated
  using (
    (select public.is_admin())
    or exists (
      select 1 from public.posts p where p.id = comments.post_id
    )
  );

drop policy if exists "User kann kommentieren" on public.comments;

drop policy if exists "User kann sichtbare Beitraege kommentieren" on public.comments;

create policy "User kann sichtbare Beitraege kommentieren"
  on public.comments
  for insert
  to authenticated
  with check (
    comments.user_id = (select auth.uid())
    and exists (
      select 1 from public.posts p where p.id = comments.post_id
    )
  );

-- Likes ----------------------------------------------------------------------
drop policy if exists "Likes sind öffentlich lesbar" on public.post_likes;

drop policy if exists "Likes nur zu sichtbaren Beitraegen" on public.post_likes;

create policy "Likes nur zu sichtbaren Beitraegen"
  on public.post_likes
  for select
  to authenticated
  using (
    (select public.is_admin())
    or exists (
      select 1 from public.posts p where p.id = post_likes.post_id
    )
  );

drop policy if exists "User kann liken" on public.post_likes;

drop policy if exists "User kann sichtbare Beitraege liken" on public.post_likes;

create policy "User kann sichtbare Beitraege liken"
  on public.post_likes
  for insert
  to authenticated
  with check (
    post_likes.user_id = (select auth.uid())
    and exists (
      select 1 from public.posts p where p.id = post_likes.post_id
    )
  );

-- Reposts --------------------------------------------------------------------
drop policy if exists "Reposts sind öffentlich lesbar" on public.reposts;

drop policy if exists "Reposts nur zu sichtbaren Beitraegen" on public.reposts;

create policy "Reposts nur zu sichtbaren Beitraegen"
  on public.reposts
  for select
  to authenticated
  using (
    (select public.is_admin())
    or exists (
      select 1 from public.posts p where p.id = reposts.post_id
    )
  );

drop policy if exists "User kann reposten" on public.reposts;

drop policy if exists "User kann sichtbare Beitraege reposten" on public.reposts;

create policy "User kann sichtbare Beitraege reposten"
  on public.reposts
  for insert
  to authenticated
  with check (
    reposts.user_id = (select auth.uid())
    and exists (
      select 1 from public.posts p where p.id = reposts.post_id
    )
  );

-- Hashtag-Zeilen -------------------------------------------------------------
-- `post_hashtags` fuellt ausschliesslich der Trigger aus dem Beitragstext.
-- Ohne diese Regel liest ein Fremder die Schlagworte eines "Nur
-- Follower"-Beitrags. Die Hashtag-Abfragen selbst (hashtag_beitraege,
-- _personen, _kennzahlen, _vorschlaege) sind SECURITY DEFINER und filtern
-- ohnehin auf visibility = 'public' — sie merken davon nichts.
drop policy if exists "post_hashtags_select_all" on public.post_hashtags;

drop policy if exists "post_hashtags_nur_sichtbare_beitraege" on public.post_hashtags;

create policy "post_hashtags_nur_sichtbare_beitraege"
  on public.post_hashtags
  for select
  to authenticated
  using (
    (select public.is_admin())
    or exists (
      select 1 from public.posts p where p.id = post_hashtags.post_id
    )
  );

-- ---------------------------------------------------------------------------
-- 4. Die beiden SECURITY-DEFINER-Umschalter gehen an der Regel vorbei.
--    Deshalb pruefen sie ab jetzt selbst. Der Rest ist unveraendert.
-- ---------------------------------------------------------------------------

create or replace function public.toggle_post_like(post_id_param uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  current_uid uuid := auth.uid();
  is_active   boolean;
  new_count   integer;
begin
  if current_uid is null then
    raise exception 'not_authenticated';
  end if;

  -- 2026-08-24: Diese Funktion laeuft als SECURITY DEFINER und sieht damit
  -- jeden Beitrag. Ohne diese Pruefung koennte ein Fremder einen "Nur
  -- Follower"-Beitrag liken, den er nicht lesen darf.
  if not exists (
    select 1
      from public.posts p
     where p.id = post_id_param
       and public.beitrag_lesbar(p.user_id, p.visibility)
  ) then
    raise exception 'beitrag_nicht_sichtbar' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.post_likes
    where post_id = post_id_param and user_id = current_uid
  ) then
    delete from public.post_likes
    where post_id = post_id_param and user_id = current_uid;

    is_active := false;
  else
    insert into public.post_likes (post_id, user_id)
    values (post_id_param, current_uid)
    on conflict (post_id, user_id) do nothing;

    is_active := true;
  end if;

  select count(*)::integer
    into new_count
    from public.post_likes
   where post_id = post_id_param;

  update public.posts
     set likes_count = new_count
   where id = post_id_param;

  return jsonb_build_object(
    'is_active', is_active,
    'count', coalesce(new_count, 0)
  );
end;
$function$;

revoke execute on function public.toggle_post_like(uuid) from public;
revoke execute on function public.toggle_post_like(uuid) from anon;
grant  execute on function public.toggle_post_like(uuid) to authenticated;

create or replace function public.toggle_post_repost(post_id_param uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  current_uid uuid := auth.uid();
  is_active   boolean;
  new_count   integer;
begin
  if current_uid is null then
    raise exception 'not_authenticated';
  end if;

  if not exists (
    select 1
      from public.posts p
     where p.id = post_id_param
       and public.beitrag_lesbar(p.user_id, p.visibility)
  ) then
    raise exception 'beitrag_nicht_sichtbar' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.reposts
    where post_id = post_id_param and user_id = current_uid
  ) then
    delete from public.reposts
    where post_id = post_id_param and user_id = current_uid;

    is_active := false;
  else
    insert into public.reposts (post_id, user_id)
    values (post_id_param, current_uid)
    on conflict (post_id, user_id) do nothing;

    is_active := true;
  end if;

  select count(*)::integer
    into new_count
    from public.reposts
   where post_id = post_id_param;

  update public.posts
     set reposts_count = new_count
   where id = post_id_param;

  return jsonb_build_object(
    'is_active', is_active,
    'count', coalesce(new_count, 0)
  );
end;
$function$;

revoke execute on function public.toggle_post_repost(uuid) from public;
revoke execute on function public.toggle_post_repost(uuid) from anon;
grant  execute on function public.toggle_post_repost(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Die Zaehler zaehlen ab jetzt nach, statt zu behaupten.
--
--    Bewusst KEINE Sichtbarkeitspruefung mit Ausnahme: eine Ausnahme wuerde
--    den Rueckfallweg im Client mitten im Ablauf abbrechen. Nachzaehlen ist
--    staerker — wer nichts einfuegen darf, hat auch nichts zu zaehlen, und
--    der Aufruf bleibt folgenlos statt fehlerhaft.
--
--    Gemessen vor der Umstellung: kein einziger Beitrag wich ab. Die
--    Umstellung aendert heute also keine Zahl, sie haelt sie nur.
-- ---------------------------------------------------------------------------

create or replace function public.increment_likes(post_id_param uuid)
returns void
language sql
security definer
set search_path to 'public', 'pg_temp'
as $$
  update public.posts p
     set likes_count = (select count(*) from public.post_likes l
                         where l.post_id = p.id)
   where p.id = post_id_param;
$$;

create or replace function public.decrement_likes(post_id_param uuid)
returns void
language sql
security definer
set search_path to 'public', 'pg_temp'
as $$
  update public.posts p
     set likes_count = (select count(*) from public.post_likes l
                         where l.post_id = p.id)
   where p.id = post_id_param;
$$;

create or replace function public.increment_comments(post_id_param uuid)
returns void
language sql
security definer
set search_path to 'public', 'pg_temp'
as $$
  update public.posts p
     set comments_count = (select count(*) from public.comments c
                            where c.post_id = p.id)
   where p.id = post_id_param;
$$;

create or replace function public.decrement_comments(post_id_param uuid)
returns void
language sql
security definer
set search_path to 'public', 'pg_temp'
as $$
  update public.posts p
     set comments_count = (select count(*) from public.comments c
                            where c.post_id = p.id)
   where p.id = post_id_param;
$$;

create or replace function public.increment_reposts(post_id_param uuid)
returns void
language sql
security definer
set search_path to 'public', 'pg_temp'
as $$
  update public.posts p
     set reposts_count = (select count(*) from public.reposts r
                           where r.post_id = p.id)
   where p.id = post_id_param;
$$;

create or replace function public.decrement_reposts(post_id_param uuid)
returns void
language sql
security definer
set search_path to 'public', 'pg_temp'
as $$
  update public.posts p
     set reposts_count = (select count(*) from public.reposts r
                           where r.post_id = p.id)
   where p.id = post_id_param;
$$;

comment on function public.increment_likes(uuid) is
  '2026-08-24: zaehlt aus post_likes nach statt +1 zu behaupten. Damit kann '
  'niemand den Zaehler eines Beitrags hochtreiben, den er nicht sehen darf.';

do $$
declare
  f text;
begin
  foreach f in array array[
    'increment_likes', 'decrement_likes',
    'increment_comments', 'decrement_comments',
    'increment_reposts', 'decrement_reposts'
  ] loop
    execute format('revoke execute on function public.%I(uuid) from public', f);
    execute format('revoke execute on function public.%I(uuid) from anon', f);
    execute format('grant  execute on function public.%I(uuid) to authenticated', f);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 6. Der Hinweispunkt am Feed-Reiter zaehlt nach derselben Regel.
--
--    Einzige Aenderung gegenueber dem Bestand: im `v_feed`-Block faellt die
--    Bedingung weg, dass der Verfasser zurueckfolgen muss. Alles andere ist
--    zeichengleich uebernommen.
-- ---------------------------------------------------------------------------

create or replace function public.community_hinweispunkte()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_uid              uuid := (select auth.uid());
  v_fenster constant interval := interval '30 days';
  v_konto            timestamptz;
  v_b_feed           timestamptz;
  v_b_gruppen        timestamptz;
  v_b_chats          timestamptz;
  v_b_entdecken      timestamptz;
  v_feed             int := 0;
  v_gruppen          int := 0;
  v_entdecken        int := 0;
  v_chats_entdecken  int := 0;
  v_chats_mitglied   int := 0;
  v_chats            int := 0;
  v_communities      jsonb := '{}'::jsonb;
begin
  if v_uid is null then
    return jsonb_build_object(
      'punkt', false,
      'reiter', jsonb_build_object(
        'feed',      jsonb_build_object('neu', false, 'anzahl', 0),
        'gruppen',   jsonb_build_object('neu', false, 'anzahl', 0),
        'chats',     jsonb_build_object('neu', false, 'anzahl', 0),
        'entdecken', jsonb_build_object('neu', false, 'anzahl', 0)),
      'communities', '{}'::jsonb,
      'stand', now());
  end if;

  select p.created_at into v_konto from public.profiles p where p.id = v_uid;
  v_konto := coalesce(v_konto, now() - v_fenster);

  select
    greatest(coalesce(max(l.gesehen_bis) filter (where l.bereich = 'feed'),      v_konto), now() - v_fenster),
    greatest(coalesce(max(l.gesehen_bis) filter (where l.bereich = 'gruppen'),   v_konto), now() - v_fenster),
    greatest(coalesce(max(l.gesehen_bis) filter (where l.bereich = 'chats'),     v_konto), now() - v_fenster),
    greatest(coalesce(max(l.gesehen_bis) filter (where l.bereich = 'entdecken'), v_konto), now() - v_fenster)
  into v_b_feed, v_b_gruppen, v_b_chats, v_b_entdecken
  from public.community_lesestand l
  where l.user_id = v_uid
    and l.community_id is null;

  -- 2026-08-24: Hier stand zusaetzlich eine Bedingung, die fuer
  -- visibility = 'followers' verlangte, dass der Verfasser ZURUECKFOLGT.
  -- Sie ist weg — einseitig folgen genuegt, wie im Feed und in der
  -- Leseregel auf `posts`. Die Stufenliste entspricht
  -- FeedSichtbarkeit.stufenVonGefolgten im Client.
  select count(*) into v_feed
  from public.posts p
  where p.created_at > v_b_feed
    and p.user_id <> v_uid
    and coalesce(p.is_hidden, false) = false
    and exists (
      select 1 from public.follows f
      where f.follower_id = v_uid and f.following_id = p.user_id
        and f.status = 'accepted')
    and coalesce(p.visibility, 'public') in ('public', 'followers')
    and not exists (
      select 1 from public.user_blocks b
      where (b.blocker_id = v_uid and b.blocked_id = p.user_id)
         or (b.blocker_id = p.user_id and b.blocked_id = v_uid));

  select
    (select count(*)
       from public.groups g
      where g.created_at > v_b_gruppen
        and g.is_public
        and g.is_active = false
        and g.closed_at is null
        and g.created_by <> v_uid
        and not exists (select 1 from public.group_members m
                         where m.group_id = g.id and m.user_id = v_uid)
        and not exists (select 1 from public.user_blocks b
                         where (b.blocker_id = v_uid and b.blocked_id = g.created_by)
                            or (b.blocker_id = g.created_by and b.blocked_id = v_uid)))
    +
    (select count(*)
       from public.group_messages gm
       join public.group_members m
         on m.group_id = gm.group_id and m.user_id = v_uid
      where gm.created_at > v_b_gruppen
        and gm.deleted_at is null
        and gm.user_id <> v_uid)
  into v_gruppen;

  select
    coalesce(jsonb_object_agg(
      t.community_id::text,
      jsonb_build_object('neu', t.anzahl > 0, 'anzahl', t.anzahl)), '{}'::jsonb),
    coalesce(sum(t.anzahl), 0)
  into v_communities, v_chats_mitglied
  from (
    select
      m.community_id,
      least(99, (
        select count(*)
        from public.community_messages cm
        where cm.community_id = m.community_id
          and cm.deleted_at is null
          and cm.user_id <> v_uid
          and cm.created_at > greatest(coalesce(l.gesehen_bis, m.created_at),
                                       now() - v_fenster)
          and not exists (
            select 1 from public.user_blocks b
            where (b.blocker_id = v_uid and b.blocked_id = cm.user_id)
               or (b.blocker_id = cm.user_id and b.blocked_id = v_uid))
      ))::int as anzahl
    from public.community_members m
    left join public.community_lesestand l
      on l.user_id = v_uid
     and l.bereich = 'community'
     and l.community_id = m.community_id
    where m.user_id = v_uid
  ) t;

  select count(*) into v_chats_entdecken
  from public.communities c
  where c.created_at > v_b_chats
    and c.is_public
    and c.owner_id <> v_uid
    and not exists (select 1 from public.community_members m
                     where m.community_id = c.id and m.user_id = v_uid)
    and not exists (select 1 from public.user_blocks b
                     where (b.blocker_id = v_uid and b.blocked_id = c.owner_id)
                        or (b.blocker_id = c.owner_id and b.blocked_id = v_uid));

  v_chats := v_chats_mitglied + v_chats_entdecken;

  select count(*) into v_entdecken
  from public.posts p
  join public.profiles a on a.id = p.user_id
  where p.created_at > v_b_entdecken
    and p.visibility = 'public'
    and coalesce(p.is_hidden, false) = false
    and p.user_id <> v_uid
    and coalesce(a.is_private, false) = false
    and coalesce(a.is_banned, false) = false
    and not exists (select 1 from public.follows f
                     where f.follower_id = v_uid and f.following_id = p.user_id
                       and f.status = 'accepted')
    and not exists (select 1 from public.user_blocks b
                     where (b.blocker_id = v_uid and b.blocked_id = p.user_id)
                        or (b.blocker_id = p.user_id and b.blocked_id = v_uid));

  return jsonb_build_object(
    'punkt', (v_feed > 0 or v_gruppen > 0 or v_chats > 0 or v_entdecken > 0),
    'reiter', jsonb_build_object(
      'feed',      jsonb_build_object('neu', v_feed      > 0, 'anzahl', least(v_feed, 99)),
      'gruppen',   jsonb_build_object('neu', v_gruppen   > 0, 'anzahl', least(v_gruppen, 99)),
      'chats',     jsonb_build_object('neu', v_chats     > 0, 'anzahl', least(v_chats, 99)),
      'entdecken', jsonb_build_object('neu', v_entdecken > 0, 'anzahl', least(v_entdecken, 99))),
    'communities', v_communities,
    'stand', now());
end;
$function$;

revoke execute on function public.community_hinweispunkte() from public;
revoke execute on function public.community_hinweispunkte() from anon;
grant  execute on function public.community_hinweispunkte() to authenticated;
