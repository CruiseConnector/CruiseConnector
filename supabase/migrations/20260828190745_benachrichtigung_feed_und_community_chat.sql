-- ---------------------------------------------------------------------------
-- 2026-08-28, Fehler 6 der Meldungen: "Wenn Nutzer denen ich folge etwas
-- posten bekomme ich keine Benachrichtigung. Wenn im Community Chat etwas
-- geschrieben wird sollen die Mitglieder benachrichtigt werden. Und man muss
-- Communities stummschalten koennen, je Community."
--
-- Die Zustell-Pipeline existiert seit dem 31.05. komplett (INSERT in
-- notifications -> pg_net-Webhook -> Edge send-push -> FCM). Es fehlten nur
-- die ERZEUGER fuer diese beiden Ereignisse. Drei Bausteine:
--
--  1. Zwei neue Typen im Check: feed_post, community_message.
--  2. community_members.stumm + RPC set_community_stumm — das Stummschalten
--     je Community, serverseitig, damit auch der Push-Fanout es sieht.
--  3. Zwei Trigger: posts -> Follower benachrichtigen;
--     community_messages -> Mitglieder benachrichtigen (ausser stumm,
--     ausser Absender, ausser blockierte Paare, mit 15-Minuten-Buendelung
--     je Community gegen Push-Gewitter in aktiven Chats).
--
-- Muster zeichengetreu nach notify_on_follow/notify_on_like (23.05.):
-- SECURITY DEFINER, Blockade-Filter wie in der Insert-Policy vom 06.05.
-- ---------------------------------------------------------------------------

-- 1. Typen erweitern. Stand vorher (aus der Produktion gelesen, inklusive
-- monitor_alarm vom 07.08.):
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in (
    'follow', 'like', 'comment', 'group_invite',
    'friend_request', 'weather_recommendation', 'trip_reminder',
    'group_ride_started', 'group_public_created', 'group_joined', 'repost',
    'monitor_alarm',
    'feed_post', 'community_message'
  ));

-- 2. Stummschalten je Community.
alter table public.community_members
  add column if not exists stumm boolean not null default false;

comment on column public.community_members.stumm is
  '2026-08-28 (Fehler 6): true = dieses Mitglied bekommt KEINE Benachrichtigungen aus dem Chat dieser Community. Nur ueber set_community_stumm schreibbar.';

create or replace function public.set_community_stumm(
  p_community_id uuid,
  p_stumm boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;
  update public.community_members
     set stumm = coalesce(p_stumm, false)
   where community_id = p_community_id and user_id = uid;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_a_member');
  end if;
  return jsonb_build_object('ok', true, 'stumm', coalesce(p_stumm, false));
end;
$$;

revoke all on function public.set_community_stumm(uuid, boolean) from public;
grant execute on function public.set_community_stumm(uuid, boolean) to authenticated;

-- 3a. Neuer Beitrag -> Follower benachrichtigen.
--
-- Sichtbarkeit ist hier bewusst KEIN Filter: posts.visibility kennt nur
-- public und followers, und Follower sehen beides. is_hidden (Moderation)
-- blockt. Ein Beitrag = eine Zeile je Follower; gebuendelt wird nicht —
-- niemand postet im Sekundentakt, und jede Zeile traegt ihren eigenen
-- Vorschautext.
create or replace function public.notify_on_feed_post()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if coalesce(new.is_hidden, false) then
    return new;
  end if;
  insert into public.notifications (user_id, from_user_id, type, reference_id, payload)
  select f.follower_id,
         new.user_id,
         'feed_post',
         new.id,
         jsonb_build_object(
           'action', 'feed_post',
           'post_id', new.id,
           'preview', left(coalesce(new.content, ''), 80)
         )
    from public.follows f
   where f.following_id = new.user_id
     and f.status = 'accepted'
     and f.follower_id <> new.user_id
     and not public.is_blocked_pair(f.follower_id, new.user_id);
  return new;
end;
$$;

drop trigger if exists trg_posts_notify_followers on public.posts;
create trigger trg_posts_notify_followers
  after insert on public.posts
  for each row execute function public.notify_on_feed_post();

-- 3b. Neue Community-Nachricht -> Mitglieder benachrichtigen.
--
-- Buendelung: hat ein Mitglied aus dieser Community schon eine UNGELESENE
-- Chat-Benachrichtigung, die juenger als 15 Minuten ist, kommt keine neue
-- dazu — sonst wird ein lebhafter Chat zum Push-Gewitter. Die bestehende
-- Zeile bekommt nur den Zaehler und die frische Vorschau.
create or replace function public.notify_on_community_message()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text;
  v_preview text;
begin
  if new.deleted_at is not null then
    return new;
  end if;
  select name into v_name from public.communities where id = new.community_id;
  v_preview := left(coalesce(nullif(btrim(coalesce(new.body, '')), ''),
                             'hat eine Route geteilt'), 80);

  -- Bestehende ungelesene Buendel-Zeilen auffrischen ...
  update public.notifications n
     set aggregate_count = n.aggregate_count + 1,
         aggregate_until = now(),
         payload = jsonb_set(
           jsonb_set(coalesce(n.payload, '{}'::jsonb),
                     '{preview}', to_jsonb(v_preview)),
           '{community_name}', to_jsonb(coalesce(v_name, 'Community')))
   where n.type = 'community_message'
     and n.reference_id = new.community_id
     and n.read = false
     and n.created_at > now() - interval '15 minutes'
     and n.user_id in (
       select m.user_id from public.community_members m
        where m.community_id = new.community_id
          and m.user_id <> new.user_id
          and m.stumm = false
     );

  -- ... und fuer alle uebrigen Empfaenger neue Zeilen anlegen.
  insert into public.notifications (user_id, from_user_id, type, reference_id, payload)
  select m.user_id,
         new.user_id,
         'community_message',
         new.community_id,
         jsonb_build_object(
           'action', 'community_message',
           'community_id', new.community_id,
           'community_name', coalesce(v_name, 'Community'),
           'message_id', new.id,
           'preview', v_preview
         )
    from public.community_members m
   where m.community_id = new.community_id
     and m.user_id <> new.user_id
     and m.stumm = false
     and not public.is_blocked_pair(m.user_id, new.user_id)
     and not exists (
       select 1 from public.notifications n
        where n.user_id = m.user_id
          and n.type = 'community_message'
          and n.reference_id = new.community_id
          and n.read = false
          and n.created_at > now() - interval '15 minutes'
     );
  return new;
end;
$$;

drop trigger if exists trg_community_messages_notify on public.community_messages;
create trigger trg_community_messages_notify
  after insert on public.community_messages
  for each row execute function public.notify_on_community_message();
