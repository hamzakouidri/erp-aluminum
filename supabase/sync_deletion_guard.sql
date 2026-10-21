-- Deletion guard for workshop_sync_rows.
--
-- On 2026-10-20 one device sent 1643 deletions in three seconds (a local wipe
-- whose rows were recorded as deletions). Each deletion replaced the row's
-- payload with {"id": ...}, so the server kept no copy, and the
-- keep-newer trigger then refused the restored rows (older updated_at).
--
-- 1. A deletion never replaces the payload: the last real copy of the row is
--    kept and the deletion details (who, from which screen) are stored
--    beside it under "_deletion". A deletion can always be undone.
-- 2. A burst of deletions of clients, orders or treasury rows is held back:
--    from the third deletion in ten minutes, when it reaches more than 10
--    rows or more than a tenth of the table, the deletion is stored in
--    workshop_sync_held_deletions instead of being applied. A manager
--    applies or discards them (functions below), or allows a deletion
--    confirmed in the app for a few minutes.
--
-- Requires sync_server_cursor.sql (server_updated_at). Safe to run more than
-- once. Apps that do not know these tables keep working.

create table if not exists public.workshop_sync_held_deletions (
  workshop_id uuid not null references public.workshops(id) on delete cascade,
  table_name text not null,
  row_id text not null,
  deleted_at timestamptz not null,
  device_id text not null default '',
  deletion jsonb not null default '{}'::jsonb,
  held_at timestamptz not null default now(),
  primary key (workshop_id, table_name, row_id)
);

create index if not exists workshop_sync_held_deletions_recent_idx
on public.workshop_sync_held_deletions (workshop_id, table_name, held_at);

create table if not exists public.workshop_mass_deletion_allowances (
  workshop_id uuid primary key references public.workshops(id) on delete cascade,
  allowed_until timestamptz not null,
  allowed_by uuid
);

create index if not exists workshop_sync_rows_deleted_recent_idx
on public.workshop_sync_rows (workshop_id, table_name, server_updated_at)
where deleted_at is not null;

alter table public.workshop_sync_held_deletions enable row level security;
alter table public.workshop_mass_deletion_allowances enable row level security;

drop policy if exists workshop_sync_held_deletions_read
  on public.workshop_sync_held_deletions;
create policy workshop_sync_held_deletions_read
on public.workshop_sync_held_deletions
for select to authenticated
using (public.is_workshop_member(workshop_id));

create or replace function public.is_workshop_manager(target_workshop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_app_admin()
    or exists (
      select 1 from public.workshops
      where id = target_workshop_id and owner_uid = (select auth.uid())
    )
    or exists (
      select 1 from public.workshop_members
      where workshop_id = target_workshop_id
        and user_id = (select auth.uid())
        and role in ('owner', 'manager', 'co_manager', 'admin')
        and blocked = false
    );
$$;

create or replace function public.workshop_sync_rows_guard_deletion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  newly_deleted boolean;
  recent_deleted integer;
  recent_held integer;
  live_rows integer;
  lost integer;
begin
  if new.deleted_at is null then
    return new;
  end if;

  newly_deleted := tg_op = 'INSERT' or old.deleted_at is null;

  -- 1. Keep the last real copy of the row.
  if tg_op = 'UPDATE' then
    if old.deleted_at is null then
      new.payload := coalesce(old.payload, '{}'::jsonb)
        || jsonb_build_object('_deletion', coalesce(new.payload, '{}'::jsonb));
    else
      new.payload := old.payload;
    end if;
  end if;

  -- 2. Hold back a burst of business deletions.
  if not newly_deleted
     or new.table_name not in ('Client', 'Commandes', 'Treasury')
     or coalesce(current_setting('app.sync_deletion_approved', true), '') = 'on'
     or exists (
       select 1 from public.workshop_mass_deletion_allowances
       where workshop_id = new.workshop_id and allowed_until > now()
     ) then
    return new;
  end if;

  select count(*) into recent_deleted
  from public.workshop_sync_rows
  where workshop_id = new.workshop_id
    and table_name = new.table_name
    and deleted_at is not null
    and server_updated_at > clock_timestamp() - interval '10 minutes';

  select count(*) into recent_held
  from public.workshop_sync_held_deletions
  where workshop_id = new.workshop_id
    and table_name = new.table_name
    and held_at > clock_timestamp() - interval '10 minutes';

  select count(*) into live_rows
  from public.workshop_sync_rows
  where workshop_id = new.workshop_id
    and table_name = new.table_name
    and deleted_at is null;

  lost := recent_deleted + recent_held + 1;
  if lost >= 3 and (lost > 10 or lost * 10 > live_rows + recent_deleted) then
    insert into public.workshop_sync_held_deletions (
      workshop_id, table_name, row_id, deleted_at, device_id, deletion, held_at
    ) values (
      new.workshop_id, new.table_name, new.row_id, new.deleted_at,
      new.device_id, coalesce(new.payload, '{}'::jsonb), now()
    )
    on conflict (workshop_id, table_name, row_id) do update
    set deleted_at = excluded.deleted_at,
        device_id = excluded.device_id,
        deletion = excluded.deletion,
        held_at = excluded.held_at;
    -- Skip this row only: the live copy stays and the rest of the batch is
    -- still written.
    return null;
  end if;

  return new;
end;
$$;

-- Runs before workshop_sync_rows_keep_newer and _server_time (triggers fire
-- in name order).
drop trigger if exists workshop_sync_rows_guard_deletion
  on public.workshop_sync_rows;
create trigger workshop_sync_rows_guard_deletion
before insert or update on public.workshop_sync_rows
for each row execute function public.workshop_sync_rows_guard_deletion();

-- A manager confirmed a large deletion in the app: accept it for a while.
create or replace function public.allow_workshop_mass_deletion(
  p_workshop_id uuid,
  p_minutes integer default 10
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_workshop_manager(p_workshop_id) then
    raise exception 'Only a workshop manager can allow a large deletion';
  end if;
  insert into public.workshop_mass_deletion_allowances (
    workshop_id, allowed_until, allowed_by
  ) values (
    p_workshop_id,
    now() + make_interval(mins => least(greatest(p_minutes, 1), 30)),
    auth.uid()
  )
  on conflict (workshop_id) do update
  set allowed_until = excluded.allowed_until,
      allowed_by = excluded.allowed_by;
end;
$$;

-- A manager accepts the held deletions: they are applied (the payload is
-- still kept by the trigger above).
create or replace function public.apply_held_workshop_deletions(
  p_workshop_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  applied integer;
begin
  if not public.is_workshop_manager(p_workshop_id) then
    raise exception 'Only a workshop manager can apply held deletions';
  end if;
  perform set_config('app.sync_deletion_approved', 'on', true);
  update public.workshop_sync_rows r
  set deleted_at = h.deleted_at,
      updated_at = greatest(r.updated_at, h.deleted_at),
      device_id = h.device_id,
      payload = h.deletion,
      revision = r.revision + 1
  from public.workshop_sync_held_deletions h
  where h.workshop_id = p_workshop_id
    and r.workshop_id = h.workshop_id
    and r.table_name = h.table_name
    and r.row_id = h.row_id
    and r.deleted_at is null;
  get diagnostics applied = row_count;
  delete from public.workshop_sync_held_deletions
  where workshop_id = p_workshop_id;
  perform set_config('app.sync_deletion_approved', '', true);
  return applied;
end;
$$;

-- A manager refuses the held deletions: the rows stay live.
create or replace function public.discard_held_workshop_deletions(
  p_workshop_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  discarded integer;
begin
  if not public.is_workshop_manager(p_workshop_id) then
    raise exception 'Only a workshop manager can discard held deletions';
  end if;
  delete from public.workshop_sync_held_deletions
  where workshop_id = p_workshop_id;
  get diagnostics discarded = row_count;
  return discarded;
end;
$$;

revoke all on function public.allow_workshop_mass_deletion(uuid, integer) from public;
revoke all on function public.apply_held_workshop_deletions(uuid) from public;
revoke all on function public.discard_held_workshop_deletions(uuid) from public;
grant execute on function public.allow_workshop_mass_deletion(uuid, integer) to authenticated;
grant execute on function public.apply_held_workshop_deletions(uuid) to authenticated;
grant execute on function public.discard_held_workshop_deletions(uuid) to authenticated;
grant execute on function public.is_workshop_manager(uuid) to authenticated;
