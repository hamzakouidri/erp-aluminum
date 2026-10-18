-- Server-side sync cursor for workshop_sync_rows.
--
-- `updated_at` carries the row's modification time on the device that edited
-- it. Incremental downloads used it as their cursor, so a row edited offline
-- (or on a device whose clock is behind) was uploaded with a time older than
-- the other devices' cursor and was never downloaded by them.
--
-- `server_updated_at` is set by the database on every insert/update and is the
-- only value clients use as a download cursor. `updated_at` keeps its meaning
-- (business modification time used to protect newer rows on upload).
--
-- Safe to run more than once. Apps that do not know the column keep working.

alter table public.workshop_sync_rows
  add column if not exists server_updated_at timestamptz;

update public.workshop_sync_rows
set server_updated_at = updated_at
where server_updated_at is null;

alter table public.workshop_sync_rows
  alter column server_updated_at set default clock_timestamp(),
  alter column server_updated_at set not null;

create or replace function public.workshop_sync_rows_set_server_time()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.server_updated_at := clock_timestamp();
  return new;
end;
$$;

drop trigger if exists workshop_sync_rows_server_time
  on public.workshop_sync_rows;
create trigger workshop_sync_rows_server_time
before insert or update on public.workshop_sync_rows
for each row execute function public.workshop_sync_rows_set_server_time();

create index if not exists workshop_sync_rows_server_updated_idx
on public.workshop_sync_rows (workshop_id, server_updated_at);
