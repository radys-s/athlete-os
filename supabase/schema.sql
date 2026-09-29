create table if not exists public.user_entities (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  kind text not null check (kind in ('plan', 'session', 'exercise', 'active', 'settings')),
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  deleted boolean not null default false,
  revision bigint not null default 1,
  primary key (user_id, id)
);

alter table public.user_entities enable row level security;

create policy "owner can select" on public.user_entities for select to authenticated
  using (auth.uid() = user_id);
-- All writes go through push_entity to preserve compare-and-swap revisions.
revoke insert, update, delete on public.user_entities from anon, authenticated;

create index if not exists user_entities_kind on public.user_entities(user_id, kind);

create or replace function public.push_entity(
  p_id text, p_kind text, p_payload jsonb, p_deleted boolean,
  p_expected_revision bigint
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  owner_id uuid := auth.uid();
  existing public.user_entities%rowtype;
  saved public.user_entities%rowtype;
begin
  if owner_id is null then raise exception 'Authentication required'; end if;
  if p_kind not in ('plan', 'session', 'exercise', 'active', 'settings') then
    raise exception 'Invalid entity kind';
  end if;
  select * into existing from public.user_entities
    where user_id = owner_id and id = p_id for update;
  if found then
    if existing.revision <> p_expected_revision then
      return jsonb_build_object('conflict', true);
    end if;
    update public.user_entities set kind = p_kind, payload = p_payload,
      deleted = p_deleted, revision = revision + 1, updated_at = now()
      where user_id = owner_id and id = p_id returning * into saved;
  else
    if p_expected_revision <> 0 then
      return jsonb_build_object('conflict', true);
    end if;
    insert into public.user_entities(user_id, id, kind, payload, deleted)
      values(owner_id, p_id, p_kind, p_payload, p_deleted)
      on conflict do nothing returning * into saved;
    if saved.id is null then return jsonb_build_object('conflict', true); end if;
  end if;
  return jsonb_build_object('conflict', false, 'revision', saved.revision,
    'updated_at', saved.updated_at);
end $$;

revoke all on function public.push_entity(text,text,jsonb,boolean,bigint) from public;
grant execute on function public.push_entity(text,text,jsonb,boolean,bigint) to authenticated;

create table if not exists public.scan_daily_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  scans integer not null check (scans between 0 and 20),
  primary key (user_id, day)
);
alter table public.scan_daily_usage enable row level security;
revoke all on public.scan_daily_usage from anon, authenticated;

create or replace function public.claim_scan() returns boolean
language plpgsql security definer set search_path = public as $$
declare claimed integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  insert into public.scan_daily_usage(user_id, day, scans)
    values (auth.uid(), (now() at time zone 'UTC')::date, 1)
    on conflict (user_id, day) do update
      set scans = public.scan_daily_usage.scans + 1
      where public.scan_daily_usage.scans < 20
    returning scans into claimed;
  return claimed is not null;
end $$;
revoke all on function public.claim_scan() from public;
grant execute on function public.claim_scan() to authenticated;
