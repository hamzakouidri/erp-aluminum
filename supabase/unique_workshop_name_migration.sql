-- Workshop names are unique regardless of letter case or surrounding spaces.
-- This migration is intentionally non-destructive: it fails if existing
-- duplicate names still need to be resolved by the administrator.

create unique index if not exists workshops_name_case_insensitive_key
on public.workshops (lower(btrim(name)))
where nullif(btrim(name), '') is not null;

create or replace function public.create_my_workshop(
  requested_join_code text,
  requested_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_code text := upper(nullif(trim(coalesce(requested_join_code, '')), ''));
  clean_name text := nullif(trim(coalesce(requested_name, '')), '');
  existing_id uuid;
  created_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if clean_code is null or clean_name is null then
    raise exception 'Workshop code and name are required';
  end if;

  select id into existing_id
  from public.workshops
  where owner_uid = auth.uid()
  order by created_at
  limit 1;
  if existing_id is not null then
    return existing_id;
  end if;

  if exists (
    select 1 from public.workshops
    where code = clean_code or join_code = clean_code
  ) then
    raise exception 'Workshop code already exists';
  end if;

  if exists (
    select 1 from public.workshops
    where nullif(btrim(name), '') is not null
      and lower(btrim(name)) = lower(btrim(clean_name))
  ) then
    raise exception 'Workshop name already exists';
  end if;

  insert into public.workshops (code, join_code, name, owner_uid)
  values (auth.uid()::text, clean_code, clean_name, auth.uid())
  returning id into created_id;

  insert into public.workshop_members (workshop_id, user_id, role)
  values (created_id, auth.uid(), 'owner')
  on conflict (workshop_id, user_id) do update set role = 'owner';
  return created_id;
end;
$$;

grant execute on function public.create_my_workshop(text, text)
to authenticated;
