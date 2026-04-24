-- Adds shared_route_id to posts so users can share a saved route in a post.
alter table public.posts
  add column if not exists shared_route_id uuid
    references public.routes(id) on delete set null;

create index if not exists posts_shared_route_id_idx
  on public.posts (shared_route_id);
