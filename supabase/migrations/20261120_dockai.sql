-- DockAI backend: API keys and quota state are never readable by anon/authenticated.
create extension if not exists pgcrypto;

create table if not exists public.dockai_admin_config (
    singleton boolean primary key default true check (singleton),
    password_hash text not null,
    updated_at timestamptz not null default now()
);

create table if not exists public.dockai_api_keys (
    id bigint generated always as identity primary key,
    api_key text not null unique check (char_length(api_key) between 20 and 200),
    created_at timestamptz not null default now(),
    disabled boolean not null default false
);

create table if not exists public.dockai_device_usage (
    device_id text primary key references public.tbs_devices(device_id) on delete cascade,
    day_start date not null default (timezone('utc', now())::date),
    week_start date not null default (date_trunc('week', timezone('utc', now()))::date),
    day_count integer not null default 0 check (day_count >= 0),
    week_count integer not null default 0 check (week_count >= 0),
    updated_at timestamptz not null default now()
);

create table if not exists public.dockai_requests (
    id uuid primary key default gen_random_uuid(),
    device_id text not null references public.tbs_devices(device_id) on delete cascade,
    day_start date not null,
    week_start date not null,
    state text not null default 'reserved' check (state in ('reserved','completed','released')),
    created_at timestamptz not null default now()
);
create index if not exists dockai_requests_device_created_idx on public.dockai_requests(device_id, created_at desc);

alter table public.dockai_admin_config enable row level security;
alter table public.dockai_api_keys enable row level security;
alter table public.dockai_device_usage enable row level security;
alter table public.dockai_requests enable row level security;
revoke all on public.dockai_admin_config, public.dockai_api_keys, public.dockai_device_usage, public.dockai_requests from anon, authenticated;
drop policy if exists dockai_config_deny_clients on public.dockai_admin_config;
create policy dockai_config_deny_clients on public.dockai_admin_config for all to anon, authenticated using (false) with check (false);
drop policy if exists dockai_keys_deny_clients on public.dockai_api_keys;
create policy dockai_keys_deny_clients on public.dockai_api_keys for all to anon, authenticated using (false) with check (false);
drop policy if exists dockai_usage_deny_clients on public.dockai_device_usage;
create policy dockai_usage_deny_clients on public.dockai_device_usage for all to anon, authenticated using (false) with check (false);
drop policy if exists dockai_requests_deny_clients on public.dockai_requests;
create policy dockai_requests_deny_clients on public.dockai_requests for all to anon, authenticated using (false) with check (false);
grant select, insert, update, delete on public.dockai_admin_config, public.dockai_api_keys, public.dockai_device_usage, public.dockai_requests to service_role;
grant usage, select on sequence public.dockai_api_keys_id_seq to service_role;

create or replace function public.dockai_reserve_usage(p_device_id text)
returns table(allowed boolean, reason text, day_used integer, week_used integer, day_limit integer, week_limit integer, day_resets_at timestamptz, week_resets_at timestamptz, request_id uuid)
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare d date := timezone('utc', now())::date; w date := date_trunc('week', timezone('utc', now()))::date; r public.dockai_device_usage%rowtype; rid uuid;
begin
  insert into public.dockai_device_usage(device_id) values (p_device_id) on conflict (device_id) do nothing;
  select * into r from public.dockai_device_usage where device_id = p_device_id for update;
  if r.day_start <> d then r.day_start := d; r.day_count := 0; end if;
  if r.week_start <> w then r.week_start := w; r.week_count := 0; end if;
  if r.week_count >= 100 then
    update public.dockai_device_usage set day_start=r.day_start, week_start=r.week_start, day_count=r.day_count, week_count=r.week_count, updated_at=now() where device_id=p_device_id;
    return query select false, 'week', r.day_count, r.week_count, 25, 100, ((d + 1)::timestamp at time zone 'utc'), ((w + 7)::timestamp at time zone 'utc'), null::uuid; return;
  end if;
  if r.day_count >= 25 then
    update public.dockai_device_usage set day_start=r.day_start, week_start=r.week_start, day_count=r.day_count, week_count=r.week_count, updated_at=now() where device_id=p_device_id;
    return query select false, 'day', r.day_count, r.week_count, 25, 100, ((d + 1)::timestamp at time zone 'utc'), ((w + 7)::timestamp at time zone 'utc'), null::uuid; return;
  end if;
  r.day_count := r.day_count + 1; r.week_count := r.week_count + 1;
  update public.dockai_device_usage set day_start=r.day_start, week_start=r.week_start, day_count=r.day_count, week_count=r.week_count, updated_at=now() where device_id=p_device_id;
  insert into public.dockai_requests(device_id, day_start, week_start) values(p_device_id, d, w) returning id into rid;
  return query select true, null::text, r.day_count, r.week_count, 25, 100, ((d + 1)::timestamp at time zone 'utc'), ((w + 7)::timestamp at time zone 'utc'), rid;
end; $$;

create or replace function public.dockai_finish_usage(p_request_id uuid, p_success boolean)
returns void language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare q public.dockai_requests%rowtype;
begin
  select * into q from public.dockai_requests where id=p_request_id and state='reserved' for update;
  if not found then return; end if;
  if p_success then
    update public.dockai_requests set state='completed' where id=p_request_id;
  else
    update public.dockai_requests set state='released' where id=p_request_id;
    update public.dockai_device_usage set day_count=greatest(0, day_count-1), week_count=greatest(0, week_count-1), updated_at=now()
      where device_id=q.device_id and day_start=q.day_start and week_start=q.week_start;
  end if;
end; $$;
revoke all on function public.dockai_reserve_usage(text) from public, anon, authenticated;
revoke all on function public.dockai_finish_usage(uuid, boolean) from public, anon, authenticated;
grant execute on function public.dockai_reserve_usage(text) to service_role;
grant execute on function public.dockai_finish_usage(uuid, boolean) to service_role;

-- The active project's admin password hash is provisioned separately and is not
-- committed here. The hosted dchat project has already been initialized.
