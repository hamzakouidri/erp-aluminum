-- Run this once in the Supabase SQL Editor.
-- The public landing page (website/index.html) reads these two totals to
-- show how many workshops and users the application has. It returns counts
-- only: no name, email or row ever leaves the database.
-- It is safe to run again because the function is replaced in place.

create or replace function public.public_site_stats()
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object(
    -- The application administrator's own workshop is not a customer.
    'workshops', (
      select count(*)
      from public.workshops w
      where not exists (
        select 1 from public.app_admins aa where aa.user_id = w.owner_uid
      )
    ),
    'members', (select count(*) from public.workshop_members)
  );
$$;

revoke all on function public.public_site_stats() from public;
grant execute on function public.public_site_stats() to anon, authenticated;
