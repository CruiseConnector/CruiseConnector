revoke execute on function public.is_blocked_pair(uuid, uuid) from public, anon;
revoke execute on function public.is_blocked_either_way(uuid) from public, anon;
revoke execute on function public.block_relationship(uuid) from public, anon;
revoke execute on function public.blocked_user_ids() from public, anon;
revoke execute on function public.block_user(uuid) from public, anon;
revoke execute on function public.unblock_user(uuid) from public, anon;

grant execute on function public.is_blocked_pair(uuid, uuid) to authenticated;
grant execute on function public.is_blocked_either_way(uuid) to authenticated;
grant execute on function public.block_relationship(uuid) to authenticated;
grant execute on function public.blocked_user_ids() to authenticated;
grant execute on function public.block_user(uuid) to authenticated;
grant execute on function public.unblock_user(uuid) to authenticated;
