-- Fix for tbs_publish_sleepscreen in 20261017_sleepscreens.sql.
-- RETURNS TABLE declares PL/pgSQL output variables named `id` and
-- `creator_account_id`; unqualified references to those table columns are
-- ambiguous at runtime. Keep this additive migration for projects where the
-- original migration has already been applied.

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
    -- creator. p_creator_account_id comes only from a verified device credential.
    select accounts.display_name into v_display_name
      from public.tbs_accounts as accounts
     where accounts.id = p_creator_account_id
     for update;
    if not found then
        outcome := 'not_found'; return next; return;
    end if;

    if p_creating then
        if p_expected_revision is not null then
            outcome := 'invalid'; return next; return;
        end if;
        select count(*) into v_count
          from public.tbs_sleepscreen_presets as presets
         where presets.creator_account_id = p_creator_account_id;
        if v_count >= 50 then
            outcome := 'quota'; return next; return;
        end if;
        if not public.tbs_sleepscreen_take_write_slot(p_creator_account_id) then
            outcome := 'rate_limited'; return next; return;
        end if;
        if exists (
            select 1 from public.tbs_sleepscreen_presets as presets
             where presets.id = p_preset_id
        ) then
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
          from public.tbs_sleepscreen_presets as presets
         where presets.id = p_preset_id
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

revoke all on function public.tbs_publish_sleepscreen(uuid, uuid, bigint, text, text, jsonb, text, boolean) from public, anon, authenticated;
grant execute on function public.tbs_publish_sleepscreen(uuid, uuid, bigint, text, text, jsonb, text, boolean) to service_role;
