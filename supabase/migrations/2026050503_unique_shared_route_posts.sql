-- A user may post a shared route only once.
-- Existing duplicates are collapsed first so the unique index can be created.
-- The newest post for each user/route pair is kept; older duplicates are
-- removed with their dependent likes, comments, and reposts.

with ranked_route_posts as (
  select
    id,
    row_number() over (
      partition by user_id, shared_route_id
      order by created_at desc nulls last, id desc
    ) as duplicate_rank
  from public.posts
  where shared_route_id is not null
)
delete from public.posts p
using ranked_route_posts r
where p.id = r.id
  and r.duplicate_rank > 1;

create unique index if not exists posts_user_shared_route_unique_idx
  on public.posts (user_id, shared_route_id)
  where shared_route_id is not null;
