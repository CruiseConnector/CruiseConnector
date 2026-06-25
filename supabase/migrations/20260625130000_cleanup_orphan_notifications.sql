-- 2026-06-25 (vucko): notifications.reference_id hat KEINEN FK → beim Löschen
-- eines Posts/einer Gruppe blieben Benachrichtigungen verwaist zurück
-- (Deeplink ins Leere = Datenmüll). Trigger räumen sie automatisch mit auf —
-- greift auch beim 24h-pg_cron-Gruppen-Cleanup. Idempotent.
create or replace function public.cleanup_notifications_for_deleted()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.notifications where reference_id = old.id;
  return old;
end;
$$;

drop trigger if exists trg_cleanup_notifs_posts on public.posts;
create trigger trg_cleanup_notifs_posts
  after delete on public.posts
  for each row execute function public.cleanup_notifications_for_deleted();

drop trigger if exists trg_cleanup_notifs_groups on public.groups;
create trigger trg_cleanup_notifs_groups
  after delete on public.groups
  for each row execute function public.cleanup_notifications_for_deleted();

-- Einmalige Bereinigung bereits verwaister Benachrichtigungen.
delete from public.notifications n
where n.reference_id is not null
  and (
    (n.type like 'group_%' and not exists
       (select 1 from public.groups g where g.id = n.reference_id))
    or
    (n.type in ('like','comment','repost') and not exists
       (select 1 from public.posts p where p.id = n.reference_id))
  );
