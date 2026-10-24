-- v1.3: a scan is reserved before the vision call and charged only when the
-- provider answers. Failed calls release the reservation.
alter table public.scan_daily_usage
  add column if not exists pending integer not null default 0
  check (pending between 0 and 20);

-- Kept for servers deployed before v1.3; respects open reservations.
create or replace function public.claim_scan() returns boolean
language plpgsql security definer set search_path = public as $$
declare claimed integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  insert into public.scan_daily_usage(user_id, day, scans)
    values (auth.uid(), (now() at time zone 'UTC')::date, 1)
    on conflict (user_id, day) do update
      set scans = public.scan_daily_usage.scans + 1
      where public.scan_daily_usage.scans + public.scan_daily_usage.pending < 20
    returning scans into claimed;
  return claimed is not null;
end $$;
revoke all on function public.claim_scan() from public;
grant execute on function public.claim_scan() to authenticated;

-- Returns the reserved UTC day, or null when the daily limit is used up.
create or replace function public.reserve_scan() returns date
language plpgsql security definer set search_path = public as $$
declare reserved date;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  insert into public.scan_daily_usage(user_id, day, scans, pending)
    values (auth.uid(), (now() at time zone 'UTC')::date, 0, 1)
    on conflict (user_id, day) do update
      set pending = public.scan_daily_usage.pending + 1
      where public.scan_daily_usage.scans + public.scan_daily_usage.pending < 20
    returning day into reserved;
  return reserved;
end $$;
revoke all on function public.reserve_scan() from public;
grant execute on function public.reserve_scan() to authenticated;

-- Charges a reserved scan. Charging does not depend on the reservation still
-- being open, so releasing it early never makes a scan free.
create or replace function public.commit_scan(p_day date) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.scan_daily_usage
    set scans = least(scans + 1, 20), pending = greatest(pending - 1, 0)
    where user_id = auth.uid() and day = p_day;
end $$;
revoke all on function public.commit_scan(date) from public;
grant execute on function public.commit_scan(date) to authenticated;

-- Returns a reservation after a failed vision call.
create or replace function public.release_scan(p_day date) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.scan_daily_usage set pending = greatest(pending - 1, 0)
    where user_id = auth.uid() and day = p_day;
end $$;
revoke all on function public.release_scan(date) from public;
grant execute on function public.release_scan(date) to authenticated;
