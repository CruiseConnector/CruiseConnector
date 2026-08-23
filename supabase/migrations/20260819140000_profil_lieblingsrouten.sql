-- 2026-08-19 (Top-3-Lieblingsrouten im Profil): Nutzer pinnen bis zu drei
-- Routen an ihr Profil, Profilbesucher sehen sie prominent.
--
-- Eigene Tabelle statt einer Spalte `profiles.featured_route_ids uuid[]`:
-- ein Array kann weder eine Fremdschluessel-Beziehung zu `routes` halten
-- (geloeschte Routen blieben als tote IDs stehen) noch laesst sich darauf
-- die Lese-Policy unten formulieren. Mit `on delete cascade` verschwindet
-- ein Highlight automatisch, sobald die Route geloescht wird.
create table if not exists public.profile_featured_routes (
  user_id uuid not null references auth.users(id) on delete cascade,
  route_id uuid not null references public.routes(id) on delete cascade,
  -- 1..3 — die Reihenfolge IST die Praesentation im Profil (Platz 1 zuerst).
  position smallint not null check (position between 1 and 3),
  created_at timestamptz not null default now(),
  -- Ein Platz je Nutzer nur einmal vergeben.
  primary key (user_id, position),
  -- Dieselbe Route nicht zweimal anpinnen.
  unique (user_id, route_id)
);

create index if not exists profile_featured_routes_user_idx
  on public.profile_featured_routes (user_id, position);
create index if not exists profile_featured_routes_route_idx
  on public.profile_featured_routes (route_id);

alter table public.profile_featured_routes enable row level security;

-- Lesen: jeder eingeloggte Nutzer, denn genau das ist der Zweck — die
-- Highlights sollen auf dem oeffentlichen Profil sichtbar sein. Die
-- Sichtbarkeit privater Profile regelt weiterhin die App-Schicht
-- (`SocialService.getProfilePreview` / Follow-Status), wie bei Posts auch.
drop policy if exists "featured_routes_select_all" on public.profile_featured_routes;
create policy "featured_routes_select_all"
  on public.profile_featured_routes for select
  to authenticated
  using (true);

-- Schreiben nur an den eigenen Zeilen. `(select auth.uid())` statt
-- `auth.uid()`, sonst wertet Postgres die Funktion je Zeile neu aus
-- (Advisor-Befund auth_rls_initplan).
drop policy if exists "featured_routes_insert_own" on public.profile_featured_routes;
create policy "featured_routes_insert_own"
  on public.profile_featured_routes for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "featured_routes_update_own" on public.profile_featured_routes;
create policy "featured_routes_update_own"
  on public.profile_featured_routes for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "featured_routes_delete_own" on public.profile_featured_routes;
create policy "featured_routes_delete_own"
  on public.profile_featured_routes for delete
  to authenticated
  using ((select auth.uid()) = user_id);


-- ─────────────────────────────────────────────────────────────
-- Ohne diese Policy waere das Feature wirkungslos.
--
-- `routes` ist fuer Fremde bisher nur lesbar, wenn `rating >= 3`
-- (20260324_security_fixes.sql). Eine selbst gefahrene Lieblingsroute hat
-- oft gar keine Bewertung — der Besucher saehe dann drei leere Kacheln.
-- Angepinnt zu sein ist eine bewusste Veroeffentlichung durch den
-- Eigentuemer und rechtfertigt den Lesezugriff, aber NUR fuer genau die
-- angepinnten Routen.
-- ─────────────────────────────────────────────────────────────
drop policy if exists "Angepinnte Lieblingsrouten sind lesbar" on public.routes;
create policy "Angepinnte Lieblingsrouten sind lesbar"
  on public.routes for select
  to authenticated
  using (
    exists (
      select 1
      from public.profile_featured_routes f
      where f.route_id = routes.id
    )
  );
