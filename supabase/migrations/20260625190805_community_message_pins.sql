alter table public.community_messages
  add column if not exists pinned_at timestamptz,
  add column if not exists pinned_by uuid references public.profiles(id) on delete set null;

create index if not exists idx_community_messages_pinned
  on public.community_messages (community_id, pinned_at desc)
  where pinned_at is not null and deleted_at is null;

create index if not exists idx_community_messages_route_attachment
  on public.community_messages (community_id, user_id, ((route_attachment ->> 'route_id')))
  where route_attachment is not null and deleted_at is null;

create or replace function public.set_community_message_pinned(
  p_message_id uuid,
  p_pinned boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_community_id uuid;
begin
  if v_actor_id is null then
    raise exception 'Bitte melde dich an.';
  end if;

  select cm.community_id into v_community_id
  from public.community_messages cm
  where cm.id = p_message_id
    and cm.deleted_at is null
  for update;

  if not found then
    raise exception 'Nachricht nicht gefunden.';
  end if;

  if not public.can_moderate_community(v_community_id, v_actor_id) then
    raise exception 'Nur Admins und Moderatoren koennen Posts anpinnen.';
  end if;

  update public.community_messages
     set pinned_at = case when p_pinned then now() else null end,
         pinned_by = case when p_pinned then v_actor_id else null end,
         updated_at = now()
   where id = p_message_id;
end;
$$;

revoke all on function public.set_community_message_pinned(uuid, boolean)
  from public;
grant execute on function public.set_community_message_pinned(uuid, boolean)
  to authenticated;
