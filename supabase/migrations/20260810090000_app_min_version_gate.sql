-- Zwangs-Update-Gate: Mindest-Build je Plattform.
--
-- Auftrag Vucko 2026-08-10: „in Zukunft wenn die App ein Update hat, dass die
-- Leute es herunterladen muessen, bevor sie in die App reingehen koennen."
--
-- Die App liest beim Start den Mindest-Build fuer ihre Plattform. Ist der
-- installierte Build KLEINER, blockiert ein Update-Screen den Zugang. Um ein
-- Update zu erzwingen, wird min_build_number hochgesetzt — kein neuer Build.
-- anon-lesbar (Check laeuft vor der Anmeldung); Schreiben nur Service-Role.
create table if not exists public.app_min_version (
  platform text primary key check (platform in ('android', 'ios')),
  min_build_number int not null default 0,
  store_url text,
  message text,
  updated_at timestamptz not null default now()
);

alter table public.app_min_version enable row level security;

drop policy if exists "app_min_version_read" on public.app_min_version;
create policy "app_min_version_read" on public.app_min_version
  for select to anon, authenticated using (true);

-- Android-Floor bewusst NIEDRIG (72), damit dieser Release niemanden aussperrt.
insert into public.app_min_version (platform, min_build_number, store_url) values
  ('android', 72, 'https://play.google.com/store/apps/details?id=com.vucko.cruiserconnect'),
  ('ios', 0, null)
on conflict (platform) do nothing;
