-- Run once in the Supabase SQL Editor after the workshop schema/migration.
-- Allows an owner/manager to create the short worker-facing code without
-- granting normal clients unrestricted UPDATE access to public.workshops.

create or replace function public.set_my_workshop_join_code(
  target_workshop_id uuid,
  requested_code text default ''
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_code text := upper(nullif(trim(coalesce(requested_code, '')), ''));
  workshop_owner uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select owner_uid
    into workshop_owner
  from public.workshops
  where id = target_workshop_id
  for update;

  if not found then
    raise exception 'Workshop was not found';
  end if;

  if not (
    public.is_app_admin()
    or workshop_owner = auth.uid()
    or exists (
      select 1
      from public.workshop_members
      where workshop_id = target_workshop_id
        and user_id = auth.uid()
        and role in ('owner', 'manager', 'co_manager', 'admin')
        and blocked = false
    )
  ) then
    raise exception 'You cannot manage this workshop';
  end if;

  if clean_code is null or clean_code !~ '^[A-Z0-9]{6}$' then
    clean_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  end if;

  loop
    exit when not exists (
      select 1 from public.workshops
      where join_code = clean_code and id <> target_workshop_id
    );
    clean_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  end loop;

  update public.workshops
  set join_code = clean_code, updated_at = now()
  where id = target_workshop_id;

  return clean_code;
end;
$$;

grant execute on function public.set_my_workshop_join_code(uuid, text)
  to authenticated;

notify pgrst, 'reload schema';
