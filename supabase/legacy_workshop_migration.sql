-- Run this once in Supabase SQL Editor after the main schema is installed.
-- It links a Supabase Auth user to an existing Firebase workshop by the old
-- owner's email and stable workshop code. It never deletes Firebase data.

alter table public.workshops
add column if not exists legacy_owner_uid text;

alter table public.workshops
add column if not exists legacy_owner_email text;

create or replace function public.claim_legacy_workshop(
  target_code text,
  target_name text default '',
  legacy_owner_email text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  clean_code text;
  clean_name text;
  old_email text;
  current_email text;
  workshop_uuid uuid;
  existing_workshop public.workshops%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  clean_code := nullif(trim(coalesce(target_code, '')), '');
  if clean_code is null then
    raise exception 'Workshop code is required';
  end if;

  clean_name := nullif(trim(coalesce(target_name, '')), '');
  current_email := lower(coalesce((select email from auth.users where id = auth.uid()), ''));
  old_email := lower(nullif(trim(coalesce(legacy_owner_email, '')), ''));

  if old_email is null or current_email = '' or old_email <> current_email then
    raise exception 'The Supabase email must match the legacy workshop owner email';
  end if;

  select * into existing_workshop
  from public.workshops
  where code = clean_code
  limit 1;

  if found then
    if not (
      public.is_app_admin()
      or existing_workshop.owner_uid = auth.uid()
      or lower(coalesce(existing_workshop.legacy_owner_email, '')) = current_email
    ) then
      raise exception 'This workshop is already owned by another account';
    end if;

    update public.workshops
    set name = case
          when clean_name is null or clean_name = '' then name
          else clean_name
        end,
        owner_uid = coalesce(owner_uid, auth.uid()),
        legacy_owner_email = current_email,
        updated_at = now()
    where id = existing_workshop.id
    returning id into workshop_uuid;
  else
    insert into public.workshops (code, name, owner_uid, legacy_owner_email)
    values (clean_code, coalesce(clean_name, clean_code), auth.uid(), current_email)
    returning id into workshop_uuid;
  end if;

  insert into public.workshop_members (workshop_id, user_id, role, updated_at)
  values (workshop_uuid, auth.uid(), 'owner', now())
  on conflict (workshop_id, user_id) do update
  set role = 'owner', blocked = false, updated_at = now();

  return workshop_uuid;
end;
$$;

grant execute on function public.claim_legacy_workshop(text, text, text) to authenticated;
