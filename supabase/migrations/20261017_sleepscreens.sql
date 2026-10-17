-- AppDock Sleep-Screen store (format v1).
--
-- Apply AFTER 20261017_tbs_account.sql in the same Supabase project, then
-- deploy the tbs-sleepscreens Edge Function.  The function uses service_role
-- only after verifying a tbs_devices SHA-256 device secret; clients never have
-- direct table or Storage access.

create table if not exists public.tbs_sleepscreen_presets (
    id uuid primary key default gen_random_uuid(),
    creator_account_id uuid not null references public.tbs_accounts(id) on delete restrict,
    name text not null check (char_length(btrim(name)) between 1 and 80),
    description text not null default '' check (char_length(description) <= 500),
    -- Canonical declarative format only.  Full field/schema and binary checks
    -- happen in the Edge Function before this data reaches Postgres.
    definition jsonb not null check (
        jsonb_typeof(definition) = 'object'
        and octet_length(definition::text) <= 9437184
    ),
    revision bigint not null default 1 check (revision >= 1),
    -- Every successful publication receives a fresh, immutable Storage prefix.
    -- The UUID attempt component prevents concurrent CAS losers from colliding.
    current_asset_prefix text not null unique check (
        current_asset_prefix ~ '^[0-9a-f-]{36}/[1-9][0-9]*/[0-9a-f-]{36}$'
    ),
    published_at timestamptz not null default now(),
    unpublished_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists tbs_sleepscreen_presets_public_catalog_idx
    on public.tbs_sleepscreen_presets (updated_at desc, id asc)
    where unpublished_at is null;
create index if not exists tbs_sleepscreen_presets_creator_idx
    on public.tbs_sleepscreen_presets (creator_account_id, created_at asc);

-- This server-only row makes the write rate limit survive Edge Function isolate
-- restarts and serialises it with the account row lock in the RPCs below.
create table if not exists public.tbs_sleepscreen_write_limits (
    creator_account_id uuid primary key references public.tbs_accounts(id) on delete cascade,
    window_started_at timestamptz not null default now(),
    write_count integer not null default 0 check (write_count between 0 and 12),
    updated_at timestamptz not null default now()
);

create or replace function public.tbs_sleepscreen_set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists tbs_sleepscreen_presets_set_updated_at on public.tbs_sleepscreen_presets;
create trigger tbs_sleepscreen_presets_set_updated_at
before update on public.tbs_sleepscreen_presets
for each row execute function public.tbs_sleepscreen_set_updated_at();

drop trigger if exists tbs_sleepscreen_write_limits_set_updated_at on public.tbs_sleepscreen_write_limits;
create trigger tbs_sleepscreen_write_limits_set_updated_at
before update on public.tbs_sleepscreen_write_limits
for each row execute function public.tbs_sleepscreen_set_updated_at();

-- This helper is intentionally not callable by client roles.  Its caller first
-- locks tbs_accounts, so insert/update races for one creator cannot bypass it.
create or replace function public.tbs_sleepscreen_take_write_slot(p_creator_account_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_window_started_at timestamptz;
    v_write_count integer;
begin
    select window_started_at, write_count
      into v_window_started_at, v_write_count
      from public.tbs_sleepscreen_write_limits
     where creator_account_id = p_creator_account_id
     for update;

    if not found then
        insert into public.tbs_sleepscreen_write_limits (creator_account_id, window_started_at, write_count)
        values (p_creator_account_id, now(), 1);
        return true;
    end if;

    if v_window_started_at <= now() - interval '60 seconds' then
        update public.tbs_sleepscreen_write_limits
           set window_started_at = now(), write_count = 1
         where creator_account_id = p_creator_account_id;
        return true;
    end if;

    if v_write_count >= 12 then return false; end if;
    update public.tbs_sleepscreen_write_limits
       set write_count = write_count + 1
     where creator_account_id = p_creator_account_id;
    return true;
end;
$$;

-- Atomically create/update a preset after assets were uploaded to a fresh,
-- unreferenced prefix.  A CAS loser cannot update the metadata and its unique
-- prefix is best-effort removed by the Edge Function.  Old prefix objects stay
-- immutable, which protects already downloaded/offline revisions.
create or replace function public.tbs_publish_sleepscreen(
    p_creator_account_id uuid,
    p_preset_id uuid,
    p_expected_revision bigint,
    p_name text,
    p_description text,
    p_definition jsonb,
    p_asset_prefix text,
    p_creating boolean
)
returns table (
    outcome text,
    id uuid,
    creator_account_id uuid,
    creator_display_name text,
    name text,
    description text,
    definition jsonb,
    revision bigint,
    published_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_preset public.tbs_sleepscreen_presets%rowtype;
    v_display_name text;
    v_count integer;
begin
    -- This authoritative lookup also serialises quota/rate-limit checks for a
    -- creator.  p_creator_account_id originates from a hashed device credential,
    -- never from a client supplied creator field.
    select display_name into v_display_name
      from public.tbs_accounts
     where id = p_creator_account_id
     for update;
    if not found then
        outcome := 'not_found'; return next; return;
    end if;

    if p_creating then
        if p_expected_revision is not null then
            outcome := 'invalid'; return next; return;
        end if;
        select count(*) into v_count
          from public.tbs_sleepscreen_presets
         where creator_account_id = p_creator_account_id;
        if v_count >= 50 then
            outcome := 'quota'; return next; return;
        end if;
        if not public.tbs_sleepscreen_take_write_slot(p_creator_account_id) then
            outcome := 'rate_limited'; return next; return;
        end if;
        -- UUID collisions are fantastically unlikely.  Checking first lets the
        -- API report a controlled conflict rather than a database constraint.
        if exists (select 1 from public.tbs_sleepscreen_presets where public.tbs_sleepscreen_presets.id = p_preset_id) then
            outcome := 'conflict'; return next; return;
        end if;
        insert into public.tbs_sleepscreen_presets (
            id, creator_account_id, name, description, definition, revision,
            current_asset_prefix, published_at
        ) values (
            p_preset_id, p_creator_account_id, p_name, p_description, p_definition, 1,
            p_asset_prefix, now()
        ) returning * into v_preset;
    else
        select * into v_preset
          from public.tbs_sleepscreen_presets
         where public.tbs_sleepscreen_presets.id = p_preset_id
         for update;
        if not found or v_preset.unpublished_at is not null then
            outcome := 'not_found'; return next; return;
        end if;
        if v_preset.creator_account_id <> p_creator_account_id then
            outcome := 'forbidden'; return next; return;
        end if;
        if p_expected_revision is null or v_preset.revision <> p_expected_revision then
            outcome := 'conflict'; return next; return;
        end if;
        if not public.tbs_sleepscreen_take_write_slot(p_creator_account_id) then
            outcome := 'rate_limited'; return next; return;
        end if;
        update public.tbs_sleepscreen_presets
           set name = p_name,
               description = p_description,
               definition = p_definition,
               revision = v_preset.revision + 1,
               current_asset_prefix = p_asset_prefix
         where public.tbs_sleepscreen_presets.id = p_preset_id
        returning * into v_preset;
    end if;

    outcome := 'ok';
    id := v_preset.id;
    creator_account_id := v_preset.creator_account_id;
    creator_display_name := v_display_name;
    name := v_preset.name;
    description := v_preset.description;
    definition := v_preset.definition;
    revision := v_preset.revision;
    published_at := v_preset.published_at;
    return next;
end;
$$;

-- Withdrawal is a soft state change: it hides the preset from public list/get
-- while retaining its revision assets.  Readers with an installed package keep
-- using it offline and no direct URL needs to survive the withdrawal.
create or replace function public.tbs_unpublish_sleepscreen(
    p_creator_account_id uuid,
    p_preset_id uuid,
    p_expected_revision bigint
)
returns table (outcome text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_preset public.tbs_sleepscreen_presets%rowtype;
begin
    perform 1 from public.tbs_accounts where id = p_creator_account_id for update;
    if not found then outcome := 'not_found'; return next; return; end if;

    select * into v_preset
      from public.tbs_sleepscreen_presets
     where public.tbs_sleepscreen_presets.id = p_preset_id
     for update;
    if not found or v_preset.unpublished_at is not null then
        outcome := 'not_found'; return next; return;
    end if;
    if v_preset.creator_account_id <> p_creator_account_id then
        outcome := 'forbidden'; return next; return;
    end if;
    if p_expected_revision is null or v_preset.revision <> p_expected_revision then
        outcome := 'conflict'; return next; return;
    end if;
    if not public.tbs_sleepscreen_take_write_slot(p_creator_account_id) then
        outcome := 'rate_limited'; return next; return;
    end if;

    update public.tbs_sleepscreen_presets
       set unpublished_at = now()
     where public.tbs_sleepscreen_presets.id = p_preset_id;
    outcome := 'ok';
    return next;
end;
$$;

-- Private Storage: the Edge Function writes/reads with service_role after its
-- own device verification.  The restrictive policy continues to deny this
-- bucket even if another project policy later permits a broader Storage role.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'appdock-sleepscreens',
    'appdock-sleepscreens',
    false,
    2097152,
    array['image/png', 'image/jpeg', 'image/webp', 'font/ttf', 'font/otf']::text[]
)
on conflict (id) do update set
    public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists appdock_sleepscreens_deny_direct_clients on storage.objects;
create policy appdock_sleepscreens_deny_direct_clients
on storage.objects as restrictive
for all to anon, authenticated
using (bucket_id <> 'appdock-sleepscreens')
with check (bucket_id <> 'appdock-sleepscreens');

-- No PostgREST or client-role table/RPC access.  Service role is intentionally
-- the only runtime principal granted access; it bypasses RLS after Edge auth.
alter table public.tbs_sleepscreen_presets enable row level security;
alter table public.tbs_sleepscreen_write_limits enable row level security;
revoke all on table public.tbs_sleepscreen_presets from anon, authenticated;
revoke all on table public.tbs_sleepscreen_write_limits from anon, authenticated;

drop policy if exists tbs_sleepscreen_presets_no_direct_access on public.tbs_sleepscreen_presets;
create policy tbs_sleepscreen_presets_no_direct_access on public.tbs_sleepscreen_presets
for all to anon, authenticated using (false) with check (false);

drop policy if exists tbs_sleepscreen_write_limits_no_direct_access on public.tbs_sleepscreen_write_limits;
create policy tbs_sleepscreen_write_limits_no_direct_access on public.tbs_sleepscreen_write_limits
for all to anon, authenticated using (false) with check (false);

grant usage on schema public to service_role;
grant select, insert, update, delete on public.tbs_sleepscreen_presets to service_role;
grant select, insert, update, delete on public.tbs_sleepscreen_write_limits to service_role;
revoke all on function public.tbs_sleepscreen_take_write_slot(uuid) from public, anon, authenticated;
revoke all on function public.tbs_publish_sleepscreen(uuid, uuid, bigint, text, text, jsonb, text, boolean) from public, anon, authenticated;
revoke all on function public.tbs_unpublish_sleepscreen(uuid, uuid, bigint) from public, anon, authenticated;
grant execute on function public.tbs_publish_sleepscreen(uuid, uuid, bigint, text, text, jsonb, text, boolean) to service_role;
grant execute on function public.tbs_unpublish_sleepscreen(uuid, uuid, bigint) to service_role;
