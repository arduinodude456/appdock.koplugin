-- TBS account storage for AppDock.
--
-- Run this migration once in the SQL editor of the SAME Supabase project that
-- serves DChat DM. The companion Edge Function is the only supported data
-- access path. It authenticates opaque per-device secrets before using the
-- service-role client; anon/authenticated PostgREST access is explicitly denied.
--
-- This migration is idempotent and stores only small JSON documents. Do not put
-- media, book files, AppDock Lua files, or private keys in tbs_account_state.

create extension if not exists pgcrypto;

create table if not exists public.tbs_accounts (
    id uuid primary key default gen_random_uuid(),
    display_name text not null check (char_length(btrim(display_name)) between 1 and 80),
    -- SHA-256 of a randomly generated high-entropy recovery code. The raw code
    -- is returned once by the Edge Function and is never stored in plaintext.
    recovery_code_hash text not null check (recovery_code_hash ~ '^[0-9a-f]{64}$'),
    preferences jsonb not null default '{}'::jsonb
        check (jsonb_typeof(preferences) = 'object' and octet_length(preferences::text) <= 32768),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.tbs_devices (
    id uuid primary key default gen_random_uuid(),
    account_id uuid not null references public.tbs_accounts(id) on delete cascade,
    -- Public routing identifier. It is not a credential.
    device_id text not null unique check (device_id ~ '^tbs_[A-Za-z0-9_-]{16,80}$'),
    -- SHA-256 of an independently random 256-bit device secret.
    device_secret_hash text not null check (device_secret_hash ~ '^[0-9a-f]{64}$'),
    device_name text not null default 'AppDock reader' check (char_length(btrim(device_name)) between 1 and 80),
    created_at timestamptz not null default now(),
    last_seen_at timestamptz not null default now(),
    revoked_at timestamptz,
    unique (account_id, device_id)
);

create index if not exists tbs_devices_account_id_idx on public.tbs_devices (account_id);
create index if not exists tbs_devices_active_idx on public.tbs_devices (account_id) where revoked_at is null;

create table if not exists public.tbs_account_state (
    account_id uuid primary key references public.tbs_accounts(id) on delete cascade,
    schema_version integer not null default 1 check (schema_version between 1 and 1000),
    revision bigint not null default 0 check (revision >= 0),
    -- AppDock's compact, sanitised migration/settings snapshot.
    state jsonb not null default '{}'::jsonb
        check (jsonb_typeof(state) = 'object' and octet_length(state::text) <= 131072),
    -- Aggregated, opt-in recommendation signals; never raw reading content.
    personalization jsonb not null default '{}'::jsonb
        check (jsonb_typeof(personalization) = 'object' and octet_length(personalization::text) <= 32768),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create or replace function public.tbs_set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists tbs_accounts_set_updated_at on public.tbs_accounts;
create trigger tbs_accounts_set_updated_at
before update on public.tbs_accounts
for each row execute function public.tbs_set_updated_at();

drop trigger if exists tbs_account_state_set_updated_at on public.tbs_account_state;
create trigger tbs_account_state_set_updated_at
before update on public.tbs_account_state
for each row execute function public.tbs_set_updated_at();

-- The Edge Function uses the Supabase service-role key and bypasses RLS after
-- authenticating a device secret itself. Direct browser/reader calls through
-- PostgREST cannot inspect, insert, or alter account data.
alter table public.tbs_accounts enable row level security;
alter table public.tbs_devices enable row level security;
alter table public.tbs_account_state enable row level security;

revoke all on table public.tbs_accounts from anon, authenticated;
revoke all on table public.tbs_devices from anon, authenticated;
revoke all on table public.tbs_account_state from anon, authenticated;

drop policy if exists tbs_accounts_no_direct_access on public.tbs_accounts;
create policy tbs_accounts_no_direct_access on public.tbs_accounts
for all to anon, authenticated using (false) with check (false);

drop policy if exists tbs_devices_no_direct_access on public.tbs_devices;
create policy tbs_devices_no_direct_access on public.tbs_devices
for all to anon, authenticated using (false) with check (false);

drop policy if exists tbs_account_state_no_direct_access on public.tbs_account_state;
create policy tbs_account_state_no_direct_access on public.tbs_account_state
for all to anon, authenticated using (false) with check (false);

grant usage on schema public to service_role;
grant select, insert, update, delete on public.tbs_accounts to service_role;
grant select, insert, update, delete on public.tbs_devices to service_role;
grant select, insert, update, delete on public.tbs_account_state to service_role;
