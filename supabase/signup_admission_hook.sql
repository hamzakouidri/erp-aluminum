-- Prevent login providers (especially Google OAuth) from creating an Auth
-- user unless the application explicitly validated the registration form.
-- Run this file in Supabase SQL Editor, then enable:
-- Authentication > Hooks > Before User Created > public.hook_admit_workshop_signup

create table if not exists public.workshop_signup_permits (
  email text primary key,
  signup_kind text not null check (signup_kind in ('manager', 'worker')),
  person_name text not null,
  workshop_name text,
  workshop_code text,
  expires_at timestamptz not null default (now() + interval '10 minutes'),
  created_at timestamptz not null default now()
);

alter table public.workshop_signup_permits enable row level security;

create or replace function public.prepare_workshop_signup(
  requested_email text,
  requested_kind text,
  requested_person_name text,
  requested_workshop_name text default '',
  requested_workshop_code text default ''
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_email text := lower(trim(coalesce(requested_email, '')));
  clean_kind text := lower(trim(coalesce(requested_kind, '')));
  clean_person_name text := trim(coalesce(requested_person_name, ''));
  clean_workshop_name text := trim(coalesce(requested_workshop_name, ''));
  clean_workshop_code text := upper(trim(coalesce(requested_workshop_code, '')));
  target_workshop_id uuid;
begin
  delete from public.workshop_signup_permits where expires_at <= now();

  if clean_email = '' or clean_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'INVALID_SIGNUP_EMAIL';
  end if;
  if clean_person_name = '' then
    raise exception 'PERSON_NAME_REQUIRED';
  end if;

  if clean_kind = 'manager' then
    if clean_workshop_name = '' then
      raise exception 'WORKSHOP_NAME_REQUIRED';
    end if;
    if exists (
      select 1 from public.workshops
      where lower(trim(name)) = lower(clean_workshop_name)
    ) then
      raise exception 'WORKSHOP_NAME_ALREADY_EXISTS';
    end if;
  elsif clean_kind = 'worker' then
    if clean_workshop_code = '' then
      raise exception 'WORKSHOP_CODE_REQUIRED';
    end if;
    select id into target_workshop_id
    from public.workshops
    where upper(trim(coalesce(join_code, code))) = clean_workshop_code
       or upper(trim(code)) = clean_workshop_code
    limit 1;
    if target_workshop_id is null then
      raise exception 'WORKSHOP_NOT_FOUND';
    end if;
    -- Verify workshop subscription capacity
    if (
      select count(*)
      from public.workshop_members
      where workshop_id = target_workshop_id
    ) >= coalesce((
      select max_users
      from public.workshop_subscriptions
      where workshop_id = target_workshop_id
    ), 4) then
      raise exception 'WORKSHOP_USER_LIMIT_REACHED';
    end if;
  else
    raise exception 'INVALID_SIGNUP_KIND';
  end if;

  insert into public.workshop_signup_permits (
    email, signup_kind, person_name, workshop_name, workshop_code, expires_at
  ) values (
    clean_email,
    clean_kind,
    clean_person_name,
    nullif(clean_workshop_name, ''),
    nullif(clean_workshop_code, ''),
    now() + interval '10 minutes'
  )
  on conflict (email) do update set
    signup_kind = excluded.signup_kind,
    person_name = excluded.person_name,
    workshop_name = excluded.workshop_name,
    workshop_code = excluded.workshop_code,
    expires_at = excluded.expires_at,
    created_at = now();

  return true;
end;
$$;

revoke all on function public.prepare_workshop_signup(text, text, text, text, text)
from public;
grant execute on function public.prepare_workshop_signup(text, text, text, text, text)
to anon, authenticated;

create or replace function public.hook_admit_workshop_signup(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  incoming_email text := lower(trim(coalesce(event->'user'->>'email', '')));
begin
  if incoming_email = '' or not exists (
    select 1 from public.workshop_signup_permits
    where email = incoming_email and expires_at > now()
  ) then
    return jsonb_build_object(
      'error', jsonb_build_object(
        'http_code', 403,
        'message', 'ACCOUNT_NOT_REGISTERED_USE_CREATE_ACCOUNT'
      )
    );
  end if;

  delete from public.workshop_signup_permits where email = incoming_email;
  return '{}'::jsonb;
end;
$$;

grant usage on schema public to supabase_auth_admin;
grant execute on function public.hook_admit_workshop_signup(jsonb)
to supabase_auth_admin;
revoke execute on function public.hook_admit_workshop_signup(jsonb)
from authenticated, anon, public;

