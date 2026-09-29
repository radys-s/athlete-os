-- v1.1: incremental pull index + account deletion.
create index if not exists user_entities_updated
  on public.user_entities(user_id, updated_at);

-- Deletes the caller's auth user; user_entities / scan_daily_usage cascade.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  delete from auth.users where id = auth.uid();
end $$;
revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
