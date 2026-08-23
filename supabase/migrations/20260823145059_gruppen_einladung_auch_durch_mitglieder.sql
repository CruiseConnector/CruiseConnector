-- 2026-08-23, Nachtrag zu 20260823144208_gruppen_einladung_sichtbarkeit.sql.
--
-- Beim Gegenlesen des Clients gemessen: Der Einladen-Knopf in der Lobby
-- (lib/presentation/pages/group_lobby_page.dart:689) ist an KEINE Rolle
-- gebunden. Jedes Mitglied kann einladen, und Mitglieder duerfen ohnehin
-- schon den Einladungscode und den Teilen-Link weitergeben. Eine RPC nur fuer
-- den Gastgeber haette diesen Weg still zerbrochen, sobald der Client von
-- `notifications.insert` auf `rpc('invite_to_group')` umgestellt wird.
--
-- Zugemacht bleibt das, was wirklich offen war: Wer weder Gastgeber noch
-- Mitglied ist, kann niemanden mehr in eine fremde private Gruppe einladen.
-- Soll es doch nur der Gastgeber duerfen, muss zuerst der Knopf in der Lobby
-- an `_hasOwnerPower` gebunden werden. Dann reicht hier eine Zeile.
--
-- Der Funktionsrumpf steht in dieser Fassung auch schon in
-- 20260823144208; diese Datei haelt fest, was in der Produktivdatenbank
-- getrennt nachgezogen wurde.
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

  if public.is_group_member(p_group_id, p_user_id) then
    return null;
  end if;

  if public.is_blocked_pair(p_user_id, v_host) then
    raise exception 'Diese Person kannst du nicht einladen.';
  end if;

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

revoke all on function public.invite_to_group(uuid, uuid) from public, anon;
grant execute on function public.invite_to_group(uuid, uuid) to authenticated;
