-- ═══════════════════════════════════════════════════════════════════════════
-- Rueckmeldung aus den Einstellungen (mit Foto)
--
-- Auftrag Vucko 2026-08-09: „Feedback-Funktion in den Einstellungen, sodass
-- die Leute mir schreiben koennen mit einem vorgefertigten Layout und der
-- Moeglichkeit, ein Foto anzuhaengen."
--
-- app_feedback gab es schon, aber nur fuer die Sterne-Abfrage nach der Fahrt:
-- stars war PFLICHT, es gab weder Kategorie noch Titel noch Bild. Diese
-- Migration oeffnet die Tabelle fuer den zweiten Weg, ohne den ersten zu
-- veraendern (source unterscheidet beide).
--
-- Das Foto liegt in einem PRIVATEN Bucket, nach Nutzer-Ordner getrennt.
-- Screenshots enthalten oft Standort, Namen oder Chatinhalte — eine
-- oeffentliche URL waere hier ein Datenleck mit Ansage.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.app_feedback
  alter column stars drop not null,
  add column if not exists category text,
  add column if not exists title text,
  add column if not exists screenshot_url text,
  add column if not exists device_info text,
  add column if not exists source text not null default 'ride_rating',
  add column if not exists status text not null default 'neu';

-- Eine Rueckmeldung ohne Sterne UND ohne Text waere leer.
alter table public.app_feedback drop constraint if exists app_feedback_hat_inhalt;
alter table public.app_feedback
  add constraint app_feedback_hat_inhalt
  check (stars is not null or coalesce(btrim(comment), '') <> '');

alter table public.app_feedback drop constraint if exists app_feedback_kategorie;
alter table public.app_feedback
  add constraint app_feedback_kategorie
  check (category is null or category in ('fehler', 'idee', 'lob', 'sonstiges'));

alter table public.app_feedback drop constraint if exists app_feedback_quelle;
alter table public.app_feedback
  add constraint app_feedback_quelle
  check (source in ('ride_rating', 'einstellungen'));

create index if not exists app_feedback_created_idx
  on public.app_feedback (created_at desc);

comment on column public.app_feedback.source is
  'ride_rating = Sterne-Abfrage nach der Fahrt, einstellungen = Formular in den Einstellungen';

-- Missbrauchsschutz: hoechstens 5 Rueckmeldungen pro Stunde und Person.
create or replace function public.app_feedback_limit()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  anzahl int;
begin
  select count(*) into anzahl
    from public.app_feedback
   where user_id = new.user_id
     and created_at > now() - interval '1 hour';
  if anzahl >= 5 then
    raise exception 'Zu viele Rueckmeldungen in kurzer Zeit. Bitte spaeter noch einmal.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_app_feedback_limit on public.app_feedback;
create trigger trg_app_feedback_limit
  before insert on public.app_feedback
  for each row execute function public.app_feedback_limit();

-- Privater Foto-Bucket, Zugriff nur auf den eigenen Ordner.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('feedback', 'feedback', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public = false,
      file_size_limit = 5242880,
      allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "feedback_upload_eigen" on storage.objects;
create policy "feedback_upload_eigen" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'feedback' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "feedback_lesen_eigen" on storage.objects;
create policy "feedback_lesen_eigen" on storage.objects
  for select to authenticated
  using (bucket_id = 'feedback' and (storage.foldername(name))[1] = auth.uid()::text);
