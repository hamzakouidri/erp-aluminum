-- Atomic last-write-wins for workshop_sync_rows.
--
-- Clients already refuse to overwrite a newer cloud row: they read the
-- remote updated_at, then upsert only rows that are not older. Between that
-- read and the write another device can store a newer version, which the
-- older upload then replaces. This trigger applies the same rule inside the
-- write itself, so an older row can never replace a newer one, whichever
-- client or app version sends it.
--
-- Equal times are accepted (same edit uploaded again). Safe to run more than
-- once.

create or replace function public.workshop_sync_rows_keep_newer()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.updated_at < old.updated_at then
    -- Skip this row only; the rest of the batch is still written.
    return null;
  end if;
  return new;
end;
$$;

drop trigger if exists workshop_sync_rows_keep_newer
  on public.workshop_sync_rows;
create trigger workshop_sync_rows_keep_newer
before update on public.workshop_sync_rows
for each row execute function public.workshop_sync_rows_keep_newer();
