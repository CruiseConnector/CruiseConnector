-- Bookmarks for shared routes.
-- A bookmark stores only the relation between a user and an existing route.

create table if not exists public.route_bookmarks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  route_id uuid not null references public.routes(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, route_id)
);

create index if not exists idx_route_bookmarks_user_created
  on public.route_bookmarks (user_id, created_at desc);

create index if not exists idx_route_bookmarks_route
  on public.route_bookmarks (route_id);

alter table public.route_bookmarks enable row level security;

drop policy if exists "User sieht eigene Routen-Lesezeichen" on public.route_bookmarks;
drop policy if exists "User speichert eigene Routen-Lesezeichen" on public.route_bookmarks;
drop policy if exists "User loescht eigene Routen-Lesezeichen" on public.route_bookmarks;

create policy "User sieht eigene Routen-Lesezeichen"
  on public.route_bookmarks for select
  using (auth.uid() = user_id);

create policy "User speichert eigene Routen-Lesezeichen"
  on public.route_bookmarks for insert
  with check (auth.uid() = user_id);

create policy "User loescht eigene Routen-Lesezeichen"
  on public.route_bookmarks for delete
  using (auth.uid() = user_id);

-- A user must be able to read a route they bookmarked so the saved list can
-- render even when the route is not one of their own routes.
drop policy if exists "Routen in eigenen Lesezeichen sind lesbar" on public.routes;
create policy "Routen in eigenen Lesezeichen sind lesbar"
  on public.routes for select
  using (
    auth.role() = 'authenticated'
    and exists (
      select 1
      from public.route_bookmarks rb
      where rb.route_id = routes.id
        and rb.user_id = auth.uid()
    )
  );

-- Shared routes should be readable where the post itself is visible to the
-- current user. Post RLS still decides which posts are visible.
drop policy if exists "Geteilte Routen sind lesbar" on public.routes;
create policy "Geteilte Routen sind lesbar"
  on public.routes for select
  using (
    auth.role() = 'authenticated'
    and exists (
      select 1
      from public.posts p
      where p.shared_route_id = routes.id
    )
  );
