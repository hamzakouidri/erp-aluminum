-- Run once in the Supabase SQL Editor.
-- `workshops.code` is the internal identifier. `join_code` is the short code
-- that a worker enters when registering in an existing workshop.

alter table public.workshops
  add column if not exists join_code text;

alter table public.workshops
  alter column join_code set default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

update public.workshops
set join_code = upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6))
where join_code is null or trim(join_code) = '';

create unique index if not exists workshops_join_code_key
  on public.workshops (join_code);

do $$
begin
  alter publication supabase_realtime add table public.workshops;
exception
  when duplicate_object then null;
  when undefined_object then null;
end
$$;

create or replace function public.ensure_my_workshop(
  target_code text,
  target_name text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_code text;
  clean_name text;
  existing_workshop public.workshops%rowtype;
  pending_invite public.workshop_member_invites%rowtype;
  workshop_uuid uuid;
  current_email text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  clean_code := upper(nullif(trim(coalesce(target_code, '')), ''));
  if clean_code is null then
    raise exception 'Workshop join code is required';
  end if;
  clean_name := nullif(trim(coalesce(target_name, '')), '');

  select lower(email) into current_email
  from auth.users where id = auth.uid() limit 1;

  select * into existing_workshop
  from public.workshops
  where code = clean_code or join_code = clean_code
  limit 1;

  if found then
    if existing_workshop.owner_uid = auth.uid()
       or public.is_app_admin()
       or exists (
         select 1 from public.workshop_members
         where workshop_id = existing_workshop.id and user_id = auth.uid()
       ) then
      workshop_uuid := existing_workshop.id;
    else
      -- The subscription limit includes the workshop owner/manager.
      if (
        select count(*)
        from public.workshop_members
        where workshop_id = existing_workshop.id
      ) >= coalesce((
        select max_users
        from public.workshop_subscriptions
        where workshop_id = existing_workshop.id
      ), 4) then
        raise exception 'WORKSHOP_USER_LIMIT_REACHED';
      end if;

      select * into pending_invite
      from public.workshop_member_invites
      where workshop_id = existing_workshop.id
        and lower(email) = current_email
      limit 1;

      if found then
        insert into public.workshop_members
          (workshop_id, user_id, role, permissions, blocked, updated_at)
        values
          (existing_workshop.id, auth.uid(), pending_invite.role,
           pending_invite.permissions, pending_invite.blocked, now())
        on conflict (workshop_id, user_id) do update
        set role = excluded.role,
            permissions = excluded.permissions,
            blocked = excluded.blocked,
            updated_at = now();
        workshop_uuid := existing_workshop.id;
      else
        -- The short workshop code is also a valid worker join credential.
        -- When a worker registers with the workshop code, create a membership
        -- in pending approval state (blocked = true, is_pending = true) until
        -- the workshop manager clicks "Accept" in the workers management screen.
        insert into public.workshop_members
          (workshop_id, user_id, role, permissions, blocked, updated_at)
        values
          (existing_workshop.id, auth.uid(), 'worker',
           '{
             "is_pending": true,
             "is_approved": false,
             "isBlocked": true,
             "view_clients": false,
             "view_orders": false,
             "view_client_details": false,
             "view_order_details": false,
             "view_my_tasks": false,
             "view_my_accreditations": false
           }'::jsonb,
           true, now())
        on conflict (workshop_id, user_id) do nothing;
        workshop_uuid := existing_workshop.id;
      end if;
    end if;

    if (existing_workshop.owner_uid = auth.uid() or public.is_app_admin())
       and clean_name is not null
       and clean_name <> ''
       and existing_workshop.name <> clean_name then
      update public.workshops
      set name = clean_name, updated_at = now()
      where id = existing_workshop.id;
    end if;
  else
    raise exception 'Workshop not found';
  end if;

  if existing_workshop.owner_uid = auth.uid() then
    insert into public.workshop_members (workshop_id, user_id, role)
    values (workshop_uuid, auth.uid(), 'owner')
    on conflict (workshop_id, user_id) do update
    set role = case
      when public.workshop_members.role = 'owner' then 'owner'
      else excluded.role
    end;
  end if;

  return workshop_uuid;
end;
$$;

grant execute on function public.ensure_my_workshop(text, text) to authenticated;

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
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  clean_code := nullif(trim(coalesce(target_code, '')), '');
  if clean_code is null then raise exception 'Workshop code is required'; end if;
  clean_name := nullif(trim(coalesce(target_name, '')), '');
  current_email := lower(coalesce((select email from auth.users where id = auth.uid()), ''));
  old_email := lower(nullif(trim(coalesce(legacy_owner_email, '')), ''));
  if old_email is null or current_email = '' or old_email <> current_email then
    raise exception 'The Supabase email must match the legacy workshop owner email';
  end if;

  select * into existing_workshop
  from public.workshops
  where code = clean_code
     or join_code = clean_code
     or lower(coalesce(legacy_owner_email, '')) = current_email
  limit 1;

  if found then
    if not (public.is_app_admin()
      or existing_workshop.owner_uid = auth.uid()
      or lower(coalesce(existing_workshop.legacy_owner_email, '')) = current_email) then
      raise exception 'This workshop is already owned by another account';
    end if;
    update public.workshops
    set name = case when clean_name is null then name else clean_name end,
        owner_uid = coalesce(owner_uid, auth.uid()),
        legacy_owner_email = current_email,
        updated_at = now()
    where id = existing_workshop.id
    returning id into workshop_uuid;
  else
    insert into public.workshops (code, name, owner_uid, legacy_owner_email)
    values (clean_code, coalesce(clean_name, ''), auth.uid(), current_email)
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

create or replace function public.update_workshop_member_permissions(
  target_code text,
  member_email text,
  member_role text,
  member_permissions jsonb,
  member_blocked boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  clean_code text;
  clean_email text;
  workshop_uuid uuid;
  target_user_id uuid;
  normalized_role text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  clean_code := nullif(trim(coalesce(target_code, '')), '');
  clean_email := lower(nullif(trim(coalesce(member_email, '')), ''));
  if clean_code is null or clean_email is null then
    raise exception 'Workshop join code and member email are required';
  end if;

  select id into workshop_uuid from public.workshops
  where code = clean_code or join_code = clean_code limit 1;
  if workshop_uuid is null then raise exception 'Workshop was not found'; end if;
  if not (public.is_app_admin() or exists (
    select 1 from public.workshop_members
    where workshop_id = workshop_uuid and user_id = auth.uid()
      and role in ('owner', 'manager', 'co_manager', 'admin')
  )) then raise exception 'You cannot manage this workshop'; end if;

  select id into target_user_id from auth.users
  where lower(email) = clean_email limit 1;
  normalized_role := coalesce(nullif(trim(member_role), ''), 'worker');
  if normalized_role not in ('owner', 'manager', 'co_manager', 'admin', 'worker') then
    normalized_role := 'worker';
  end if;

  if target_user_id is null then
    insert into public.workshop_member_invites
      (workshop_id, email, role, permissions, blocked, updated_at)
    values
      (workshop_uuid, clean_email, normalized_role,
       coalesce(member_permissions, '{}'::jsonb), coalesce(member_blocked, false), now())
    on conflict (workshop_id, email) do update
    set role = excluded.role, permissions = excluded.permissions,
        blocked = excluded.blocked, updated_at = now();
    return true;
  end if;

  insert into public.workshop_members
    (workshop_id, user_id, role, permissions, blocked, updated_at)
  values
    (workshop_uuid, target_user_id, normalized_role,
     coalesce(member_permissions, '{}'::jsonb), coalesce(member_blocked, false), now())
  on conflict (workshop_id, user_id) do update
  set role = excluded.role, permissions = excluded.permissions,
      blocked = excluded.blocked, updated_at = now();
  return true;
end;
$$;

grant execute on function public.update_workshop_member_permissions(text, text, text, jsonb, boolean) to authenticated;

create or replace function public.list_workshop_members(target_code text)
returns table (
  user_id uuid, email text, role text, permissions jsonb, blocked boolean,
  is_pending boolean, updated_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  clean_code text;
  workshop_uuid uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  clean_code := nullif(trim(coalesce(target_code, '')), '');
  if clean_code is null then raise exception 'Workshop join code is required'; end if;
  select id into workshop_uuid from public.workshops
  where code = clean_code or join_code = clean_code limit 1;
  if workshop_uuid is null then raise exception 'Workshop was not found'; end if;
  if not (public.is_app_admin() or exists (
    select 1 from public.workshop_members wm
    where wm.workshop_id = workshop_uuid and wm.user_id = auth.uid()
      and wm.role in ('owner', 'manager', 'co_manager', 'admin')
  )) then raise exception 'You cannot view workshop members'; end if;

  return query
  select m.user_id, coalesce(u.email, '')::text, m.role, m.permissions,
         m.blocked, false, m.updated_at
  from public.workshop_members m
  left join auth.users u on u.id = m.user_id
  where m.workshop_id = workshop_uuid and m.role <> 'owner';

  return query
  select null::uuid, i.email, i.role, i.permissions, i.blocked, true, i.updated_at
  from public.workshop_member_invites i
  where i.workshop_id = workshop_uuid
    and not exists (
      select 1 from auth.users u
      join public.workshop_members m on m.workshop_id = i.workshop_id
        and m.user_id = u.id
      where lower(u.email) = lower(i.email)
    );
end;
$$;

grant execute on function public.list_workshop_members(text) to authenticated;

create or replace function public.list_admin_workshops()
returns table (
  workshop_id uuid, code text, name text, owner_uid uuid, owner_email text,
  status text, plan_type text, starts_at timestamptz, ends_at timestamptz,
  max_users integer, max_systems integer, max_profiles integer, member_count bigint
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_app_admin() then
    raise exception 'Only application administrators can list workshops';
  end if;
  return query
  select w.id, coalesce(w.join_code, w.code)::text, w.name, w.owner_uid,
    coalesce(owner_user.email, '')::text, coalesce(s.status, 'expired')::text,
    coalesce(s.plan_type, 'trial')::text, s.starts_at, s.ends_at,
    coalesce(s.max_users, 4), coalesce(s.max_systems, 999),
    coalesce(s.max_profiles, 999),
    (select count(*) from public.workshop_members m where m.workshop_id = w.id)
  from public.workshops w
  left join public.workshop_subscriptions s on s.workshop_id = w.id
  left join auth.users owner_user on owner_user.id = w.owner_uid
  order by w.created_at desc;
end;
$$;

grant execute on function public.list_admin_workshops() to authenticated;
notify pgrst, 'reload schema';
