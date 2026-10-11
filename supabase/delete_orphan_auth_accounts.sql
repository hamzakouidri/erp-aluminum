-- Run once in the Supabase SQL Editor.
--
-- Registration creates auth.users before the application can create/join a
-- workshop. If the second step fails, this RPC lets that same authenticated
-- user remove its orphan Auth row. It cannot delete an owner or a member of
-- any workshop.

create or replace function public.delete_current_orphan_auth_user()
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  deleted_rows integer := 0;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if exists (
       select 1 from public.workshops where owner_uid = auth.uid()
     ) or exists (
       select 1 from public.workshop_members where user_id = auth.uid()
     ) then
    raise exception 'configured workshop account cannot be deleted here';
  end if;

  delete from auth.users where id = auth.uid();
  get diagnostics deleted_rows = row_count;
  return deleted_rows = 1;
end;
$$;

revoke all on function public.delete_current_orphan_auth_user() from public;
grant execute on function public.delete_current_orphan_auth_user()
to authenticated;

-- Retain the old RPC name for installed application versions.
create or replace function public.delete_unconfigured_auth_user()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if exists (
       select 1 from public.workshops where owner_uid = auth.uid()
     ) or exists (
       select 1 from public.workshop_members where user_id = auth.uid()
     ) then
    raise exception 'configured workshop account cannot be deleted here';
  end if;

  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_unconfigured_auth_user() from public;
grant execute on function public.delete_unconfigured_auth_user()
to authenticated;
