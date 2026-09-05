-- Prevent every client-side authentication/synchronization path from creating
-- an empty workshop when a code is stale, mistyped, or no longer assigned.
-- Existing workshops and memberships are preserved.

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
    raise exception 'Workshop code is required';
  end if;

  select lower(email)
  into current_email
  from auth.users
  where id = auth.uid()
  limit 1;

  select *
  into existing_workshop
  from public.workshops
  where code = clean_code or join_code = clean_code
  limit 1;

  if not found then
    raise exception 'Workshop not found';
  end if;

  if existing_workshop.owner_uid = auth.uid()
     or public.is_app_admin()
     or exists (
       select 1
       from public.workshop_members
       where workshop_id = existing_workshop.id
         and user_id = auth.uid()
     ) then
    workshop_uuid := existing_workshop.id;
  else
    select *
    into pending_invite
    from public.workshop_member_invites
    where workshop_id = existing_workshop.id
      and lower(email) = current_email
    limit 1;

    if found then
      insert into public.workshop_members (
        workshop_id, user_id, role, permissions, blocked, updated_at
      )
      values (
        existing_workshop.id, auth.uid(), pending_invite.role,
        pending_invite.permissions, pending_invite.blocked, now()
      )
      on conflict (workshop_id, user_id) do update
      set role = excluded.role,
          permissions = excluded.permissions,
          blocked = excluded.blocked,
          updated_at = now();
      workshop_uuid := existing_workshop.id;
    else
      -- A valid short code can join an existing workshop, but it can never
      -- create a new workshop when the code is wrong.
      insert into public.workshop_members (
        workshop_id, user_id, role, permissions, blocked, updated_at
      )
      values (
        existing_workshop.id,
        auth.uid(),
        'worker',
        '{
          "view_clients": true,
          "view_orders": true,
          "view_client_details": true,
          "view_order_details": true,
          "view_my_tasks": true,
          "view_my_accreditations": true
        }'::jsonb,
        false,
        now()
      )
      on conflict (workshop_id, user_id) do nothing;
      workshop_uuid := existing_workshop.id;
    end if;
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

grant execute on function public.ensure_my_workshop(text, text)
to authenticated;

-- The only allowed creation path: the user explicitly chose "new workshop"
-- during registration. Repeating the request is idempotent for the same owner.
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
