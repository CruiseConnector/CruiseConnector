-- Store user-submitted reports for posts, comments, and profiles.
-- Admin review/notification workflows can build on this table later.

create table if not exists public.content_reports (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_user_id uuid references auth.users(id) on delete set null,
  post_id uuid references public.posts(id) on delete set null,
  comment_id uuid references public.comments(id) on delete set null,
  target_type text not null,
  target_snapshot jsonb not null default '{}'::jsonb,
  reason text not null,
  details text,
  status text not null default 'open',
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  admin_notes text,
  constraint content_reports_reason_check check (
    reason in (
      'spam',
      'harassment',
      'hate_speech',
      'sexual_content',
      'violence',
      'self_harm',
      'illegal',
      'other'
    )
  ),
  constraint content_reports_status_check check (
    status in ('open', 'reviewing', 'resolved', 'dismissed')
  ),
  constraint content_reports_target_type_check check (
    target_type in ('user', 'post', 'comment')
  ),
  constraint content_reports_has_target_check check (
    (
      case when reported_user_id is null then 0 else 1 end
      + case when post_id is null then 0 else 1 end
      + case when comment_id is null then 0 else 1 end
    ) > 0
  )
);

alter table public.content_reports enable row level security;

drop policy if exists "Users can create own content reports" on public.content_reports;
create policy "Users can create own content reports"
  on public.content_reports for insert
  with check (auth.uid() = reporter_id);

drop policy if exists "Users can view own content reports" on public.content_reports;
create policy "Users can view own content reports"
  on public.content_reports for select
  using (auth.uid() = reporter_id);

create index if not exists idx_content_reports_status_created
  on public.content_reports (status, created_at desc);

create index if not exists idx_content_reports_reporter_created
  on public.content_reports (reporter_id, created_at desc);

create index if not exists idx_content_reports_reported_user_created
  on public.content_reports (reported_user_id, created_at desc)
  where reported_user_id is not null;

create index if not exists idx_content_reports_post_created
  on public.content_reports (post_id, created_at desc)
  where post_id is not null;

create index if not exists idx_content_reports_comment_created
  on public.content_reports (comment_id, created_at desc)
  where comment_id is not null;

create or replace function public.set_content_report_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_content_reports_updated_at on public.content_reports;
create trigger trg_content_reports_updated_at
  before update on public.content_reports
  for each row
  execute function public.set_content_report_updated_at();

drop function if exists public.submit_content_report(text, uuid, uuid, uuid, text);

create function public.submit_content_report(
  p_reason text,
  p_reported_user_id uuid default null,
  p_post_id uuid default null,
  p_comment_id uuid default null,
  p_details text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reporter_id uuid := auth.uid();
  v_reason text := lower(trim(coalesce(p_reason, '')));
  v_details text := nullif(left(trim(coalesce(p_details, '')), 1000), '');
  v_reported_user_id uuid := p_reported_user_id;
  v_post_id uuid := p_post_id;
  v_target_type text;
  v_target_snapshot jsonb := '{}'::jsonb;
  v_post_snapshot jsonb;
  v_comment_snapshot jsonb;
  v_user_snapshot jsonb;
  v_post_author_id uuid;
  v_comment_author_id uuid;
  v_comment_post_id uuid;
  v_report_id uuid;
begin
  if v_reporter_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_reported_user_id is null and p_post_id is null and p_comment_id is null then
    raise exception 'missing_report_target' using errcode = '22023';
  end if;

  if v_reason not in (
    'spam',
    'harassment',
    'hate_speech',
    'sexual_content',
    'violence',
    'self_harm',
    'illegal',
    'other'
  ) then
    raise exception 'invalid_report_reason' using errcode = '22023';
  end if;

  if p_comment_id is not null then
    select
      jsonb_build_object(
        'id', c.id,
        'post_id', c.post_id,
        'user_id', c.user_id,
        'content', left(c.content, 1000),
        'created_at', c.created_at
      ),
      c.user_id,
      c.post_id
    into v_comment_snapshot, v_comment_author_id, v_comment_post_id
    from public.comments c
    where c.id = p_comment_id;

    if v_comment_snapshot is null then
      raise exception 'comment_not_found' using errcode = '22023';
    end if;

    v_target_snapshot := v_target_snapshot
      || jsonb_build_object('comment', v_comment_snapshot);
    v_reported_user_id := coalesce(v_reported_user_id, v_comment_author_id);
    v_post_id := coalesce(v_post_id, v_comment_post_id);
  end if;

  if v_post_id is not null then
    select
      jsonb_build_object(
        'id', p.id,
        'user_id', p.user_id,
        'content', left(p.content, 1000),
        'created_at', p.created_at
      ),
      p.user_id
    into v_post_snapshot, v_post_author_id
    from public.posts p
    where p.id = v_post_id;

    if v_post_snapshot is null then
      raise exception 'post_not_found' using errcode = '22023';
    end if;

    v_target_snapshot := v_target_snapshot
      || jsonb_build_object('post', v_post_snapshot);
    v_reported_user_id := coalesce(v_reported_user_id, v_post_author_id);
  end if;

  if v_reported_user_id is not null then
    if v_reported_user_id = v_reporter_id then
      raise exception 'self_report_not_allowed' using errcode = '22023';
    end if;

    select jsonb_build_object(
      'id', p.id,
      'username', p.username,
      'avatar_url', p.avatar_url,
      'created_at', p.created_at
    )
    into v_user_snapshot
    from public.profiles p
    where p.id = v_reported_user_id;

    v_target_snapshot := v_target_snapshot
      || jsonb_build_object(
        'user',
        coalesce(v_user_snapshot, jsonb_build_object('id', v_reported_user_id))
      );
  end if;

  v_target_type := case
    when p_comment_id is not null then 'comment'
    when v_post_id is not null then 'post'
    else 'user'
  end;

  select id
    into v_report_id
  from public.content_reports
  where reporter_id = v_reporter_id
    and status in ('open', 'reviewing')
    and reported_user_id is not distinct from v_reported_user_id
    and post_id is not distinct from v_post_id
    and comment_id is not distinct from p_comment_id
  order by created_at desc
  limit 1;

  if v_report_id is not null then
    update public.content_reports
    set reason = v_reason,
        details = coalesce(v_details, details),
        target_snapshot = v_target_snapshot
    where id = v_report_id;

    return v_report_id;
  end if;

  insert into public.content_reports (
    reporter_id,
    reported_user_id,
    post_id,
    comment_id,
    target_type,
    target_snapshot,
    reason,
    details
  )
  values (
    v_reporter_id,
    v_reported_user_id,
    v_post_id,
    p_comment_id,
    v_target_type,
    v_target_snapshot,
    v_reason,
    v_details
  )
  returning id into v_report_id;

  return v_report_id;
end;
$$;

revoke all on function public.submit_content_report(text, uuid, uuid, uuid, text)
  from public;

grant execute on function public.submit_content_report(text, uuid, uuid, uuid, text)
  to authenticated;
