-- 2026-07-10 (vucko): Fix doppelte Follow-Benachrichtigung.
-- Ursache: pro Follow wurden ZWEI notifications-Zeilen erzeugt — eine vom Client
-- (SocialService.followUser) und eine vom DB-Trigger notify_on_follow(). Weil der
-- In-App-Text deterministisch pro notification.id aus einem Varianten-Pool gewählt
-- wird, sahen die zwei Zeilen unterschiedlich aus ("Neuer Follower" vs "Cruiser
-- folgt dir"). Zusätzlich feuerte der Push-Webhook pro Zeile → zwei Pushes.
-- Fix: Client-Insert entfernt (siehe social_service.dart), Trigger = einzige Quelle,
-- jetzt statusbewusst; echter Unique-Index als DB-Sperre; Alt-Duplikate bereinigt.

create or replace function public.notify_on_follow()
returns trigger language plpgsql security definer set search_path = public as $$
declare ntype text;
begin
  if new.follower_id = new.following_id then return new; end if;
  -- pending (privates Konto) -> 'friend_request', sonst -> 'follow'
  ntype := case when new.status = 'pending' then 'friend_request' else 'follow' end;
  insert into notifications (user_id, from_user_id, type, reference_id, payload)
  values (new.following_id, new.follower_id, ntype, new.id, jsonb_build_object('action', ntype))
  on conflict do nothing;
  return new;
end $$;

-- Alt-Duplikate: die vom Client eingefügte Zeile (reference_id IS NULL) löschen,
-- wenn eine Trigger-Zeile (reference_id gesetzt) für dasselbe Paar in +/-10s existiert.
delete from notifications c
where c.type = 'follow'
  and c.reference_id is null
  and exists (
    select 1 from notifications t
    where t.type in ('follow','friend_request')
      and t.reference_id is not null
      and t.user_id = c.user_id
      and t.from_user_id = c.from_user_id
      and abs(extract(epoch from (t.created_at - c.created_at))) < 10
  );

-- Unique-Index gegen künftige Doppel-Inserts (nur Follow-Typen, nur Trigger-Zeilen).
-- reference_id=follows.id ist pro Follow eindeutig -> Re-Follows NICHT blockiert,
-- Likes/Kommentare (die reference_id teilen) NICHT betroffen.
create unique index if not exists uniq_follow_notif
  on notifications (reference_id, type)
  where reference_id is not null and type in ('follow','friend_request');
