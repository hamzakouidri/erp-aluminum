create table if not exists public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- Add the UUID of the application-admin Supabase Auth user here after the
-- first account is created. Do not use a workshop role or a client-side email
-- check as a substitute: RLS uses this table as the server-side authority.

create or replace function public.is_app_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.app_admins
    where user_id = (select auth.uid())
  ) or lower(coalesce((
    select email from auth.users where id = (select auth.uid())
  ), '')) = 'kouidrihamza45@gmail.com';
$$;

create table if not exists public.catalog_manifest (
  id text primary key,
  version_id text not null,
  status text not null check (status in ('uploading', 'completed')),
  tables jsonb not null default '[]'::jsonb,
  table_row_counts jsonb not null default '{}'::jsonb,
  chunk_counts jsonb not null default '{}'::jsonb,
  uploader_uid uuid,
  updated_at timestamptz not null default now()
);

create table if not exists public.catalog_chunks (
  version_id text not null,
  table_name text not null,
  chunk_index integer not null,
  total_chunks integer not null,
  row_count integer not null,
  payload jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  primary key (version_id, table_name, chunk_index)
);

create index if not exists catalog_chunks_version_idx
on public.catalog_chunks (version_id);

create table if not exists public.workshops (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  join_code text unique not null default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6)),
  name text not null default '',
  owner_uid uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- The internal workshop code and the code shared with workers are different
-- values. Add the public registration code to existing installations too.
alter table public.workshops
add column if not exists join_code text;

alter table public.workshops
alter column join_code set default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

update public.workshops
set join_code = upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6))
where join_code is null or trim(join_code) = '';

create unique index if not exists workshops_join_code_key
on public.workshops (join_code);

-- Legacy Firebase identity is kept only as migration metadata. It must not be
-- placed in owner_uid/user_id because those columns reference Supabase Auth.
alter table public.workshops
add column if not exists legacy_owner_uid text;

alter table public.workshops
add column if not exists legacy_owner_email text;

create table if not exists public.workshop_members (
  workshop_id uuid not null references public.workshops(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'worker' check (role in ('owner', 'manager', 'co_manager', 'admin', 'worker')),
  permissions jsonb not null default '{}'::jsonb,
  blocked boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (workshop_id, user_id)
);

create table if not exists public.workshop_member_invites (
  workshop_id uuid not null references public.workshops(id) on delete cascade,
  email text not null,
  role text not null default 'worker' check (role in ('owner', 'manager', 'co_manager', 'admin', 'worker')),
  permissions jsonb not null default '{}'::jsonb,
  blocked boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (workshop_id, email)
);

create index if not exists workshop_member_invites_email_idx
on public.workshop_member_invites (lower(email));

alter table public.workshop_members
add column if not exists permissions jsonb not null default '{}'::jsonb;

alter table public.workshop_members
add column if not exists blocked boolean not null default false;

alter table public.workshop_members
add column if not exists updated_at timestamptz not null default now();

alter table public.workshop_member_invites
add column if not exists permissions jsonb not null default '{}'::jsonb;

alter table public.workshop_member_invites
add column if not exists blocked boolean not null default false;

alter table public.workshop_member_invites
add column if not exists updated_at timestamptz not null default now();

do $$
begin
  alter table public.workshop_members
  drop constraint if exists workshop_members_role_check;

  alter table public.workshop_members
  add constraint workshop_members_role_check
  check (role in ('owner', 'manager', 'co_manager', 'admin', 'worker'));

  alter table public.workshop_member_invites
  drop constraint if exists workshop_member_invites_role_check;

  alter table public.workshop_member_invites
  add constraint workshop_member_invites_role_check
  check (role in ('owner', 'manager', 'co_manager', 'admin', 'worker'));
end
$$;

notify pgrst, 'reload schema';

-- -------------------------------------------------------------------------
-- Supabase-authoritative workshop subscriptions
-- -------------------------------------------------------------------------
-- Subscription state belongs to the workshop, not to an individual device
-- or a Firebase user document.  A worker therefore inherits exactly the
-- same limits and expiry as the workshop owner.
create table if not exists public.workshop_subscriptions (
  workshop_id uuid primary key references public.workshops(id) on delete cascade,
  status text not null default 'trialing',
  plan_type text not null default 'trial',
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  max_users integer not null default 4,
  max_systems integer not null default 999,
  max_profiles integer not null default 999,
  updated_at timestamptz not null default now()
);

create index if not exists workshop_subscriptions_status_idx
on public.workshop_subscriptions (status, ends_at);

create or replace function public.create_default_workshop_subscription()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.workshop_subscriptions (
    workshop_id, status, plan_type, starts_at, ends_at,
    max_users, max_systems, max_profiles
  )
  values (
    new.id, 'trialing', 'trial', now(), now() - interval '1 day',
    4, 999, 999
  )
  on conflict (workshop_id) do nothing;
  return new;
end;
$$;

drop trigger if exists workshops_create_default_subscription
on public.workshops;
create trigger workshops_create_default_subscription
after insert on public.workshops
for each row execute function public.create_default_workshop_subscription();

insert into public.workshop_subscriptions (workshop_id, status, plan_type, starts_at, ends_at)
select id, 'trialing', 'trial', created_at, created_at - interval '1 day'
from public.workshops
where not exists (
  select 1 from public.workshop_subscriptions s
  where s.workshop_id = public.workshops.id
);

alter table public.workshop_subscriptions enable row level security;

create or replace function public.admin_set_workshop_subscription(
  target_workshop_id uuid,
  new_status text,
  new_plan_type text default 'yearly',
  new_ends_at timestamptz default null,
  new_max_users integer default 4,
  new_max_systems integer default 999,
  new_max_profiles integer default 999
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_app_admin() then
    raise exception 'Only application administrators can change subscriptions';
  end if;

  insert into public.workshop_subscriptions (
    workshop_id, status, plan_type, starts_at, ends_at,
    max_users, max_systems, max_profiles, updated_at
  )
  values (
    target_workshop_id,
    coalesce(nullif(trim(new_status), ''), 'expired'),
    coalesce(nullif(trim(new_plan_type), ''), 'yearly'),
    now(), new_ends_at,
    greatest(coalesce(new_max_users, 4), 0),
    greatest(coalesce(new_max_systems, 999), 0),
    greatest(coalesce(new_max_profiles, 999), 0),
    now()
  )
  on conflict (workshop_id) do update set
    status = excluded.status,
    plan_type = excluded.plan_type,
    starts_at = excluded.starts_at,
    ends_at = excluded.ends_at,
    max_users = excluded.max_users,
    max_systems = excluded.max_systems,
    max_profiles = excluded.max_profiles,
    updated_at = now();
end;
$$;

grant execute on function public.admin_set_workshop_subscription(
  uuid, text, text, timestamptz, integer, integer, integer
) to authenticated;

create or replace function public.is_workshop_member(target_workshop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_app_admin()
    or exists (
      select 1
      from public.workshop_members
      where workshop_id = target_workshop_id
        and user_id = (select auth.uid())
    );
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
    clean_code := auth.uid()::text;
  end if;
  clean_name := nullif(trim(coalesce(target_name, '')), '');
  if clean_name is null then
    clean_name := clean_code;
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

  if found then
    if (existing_workshop.owner_uid = auth.uid() or public.is_app_admin())
       and clean_name <> ''
       and existing_workshop.name <> clean_name then
      update public.workshops
      set name = clean_name,
          updated_at = now()
      where id = existing_workshop.id;
      existing_workshop.name := clean_name;
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
      -- max_users includes the workshop owner/manager. Enforce this in the
      -- database so parallel devices cannot bypass the subscription limit.
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

      select *
      into pending_invite
      from public.workshop_member_invites
      where workshop_id = existing_workshop.id
        and lower(email) = current_email
      limit 1;

      if found then
        insert into public.workshop_members (
          workshop_id,
          user_id,
          role,
          permissions,
          blocked,
          updated_at
        )
        values (
          existing_workshop.id,
          auth.uid(),
          pending_invite.role,
          pending_invite.permissions,
          pending_invite.blocked,
          now()
        )
        on conflict (workshop_id, user_id) do update
        set role = excluded.role,
            permissions = excluded.permissions,
            blocked = excluded.blocked,
            updated_at = now();

        workshop_uuid := existing_workshop.id;
      else
        -- The short workshop code submits a join request.  It proves which
        -- workshop the worker is asking for, but it must never grant access
        -- before a manager explicitly approves the request.
        insert into public.workshop_members (
          workshop_id,
          user_id,
          role,
          permissions,
          blocked,
          updated_at
        )
        values (
          existing_workshop.id,
          auth.uid(),
          'worker',
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
          true,
          now()
        )
        on conflict (workshop_id, user_id) do nothing;
        workshop_uuid := existing_workshop.id;
      end if;
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
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if clean_code is null or clean_name is null then
    raise exception 'Workshop code and name are required';
  end if;
  select id into existing_id from public.workshops
  where owner_uid = auth.uid() order by created_at limit 1;
  if existing_id is not null then return existing_id; end if;
  if exists (select 1 from public.workshops
             where code = clean_code or join_code = clean_code) then
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

-- Google/OAuth can create auth.users before the app finishes registration.
-- Allow the signed-in user to remove only that orphan account; configured
-- owners or members are protected from this cleanup path.
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
  if exists (select 1 from public.workshops where owner_uid = auth.uid())
     or exists (select 1 from public.workshop_members where user_id = auth.uid()) then
    raise exception 'configured workshop account cannot be deleted here';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_unconfigured_auth_user() from public;
grant execute on function public.delete_unconfigured_auth_user() to authenticated;

grant execute on function public.create_my_workshop(text, text)
to authenticated;

-- Keep workshop-code creation in the main schema deployment.  This used to
-- live only in an optional migration, so managers received an RLS error when
-- the app tried to create a code on an existing workshop.
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
        and user_id = (select auth.uid())
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
      select 1
      from public.workshops
      where join_code = clean_code
        and id <> target_workshop_id
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

-- One-time bridge for workshops created before the move from Firebase Auth.
-- The caller must be logged into Supabase with the same email as the old
-- Firebase owner. Firebase UIDs remain text metadata only; the active member
-- row always uses the new Supabase auth.uid().
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
     or join_code = clean_code
     or lower(coalesce(legacy_owner_email, '')) = current_email
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
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  clean_code := nullif(trim(coalesce(target_code, '')), '');
  clean_email := lower(nullif(trim(coalesce(member_email, '')), ''));
  if clean_code is null or clean_email is null then
    raise exception 'Workshop code and member email are required';
  end if;

  select id
  into workshop_uuid
  from public.workshops
  where code = clean_code or join_code = clean_code
  limit 1;

  if workshop_uuid is null then
    workshop_uuid := public.ensure_my_workshop(clean_code, clean_code);
  end if;

  if not (
    public.is_app_admin()
    or exists (
      select 1
      from public.workshop_members wm
      where wm.workshop_id = workshop_uuid
        and wm.user_id = auth.uid()
        and wm.role in ('owner', 'manager', 'co_manager', 'admin')
    )
  ) then
    raise exception 'You cannot manage this workshop';
  end if;

  select id
  into target_user_id
  from auth.users
  where lower(email) = clean_email
  limit 1;

  if target_user_id is null then
    normalized_role := coalesce(nullif(trim(member_role), ''), 'worker');
    if normalized_role not in ('owner', 'manager', 'co_manager', 'admin', 'worker') then
      normalized_role := 'worker';
    end if;

    insert into public.workshop_member_invites (
      workshop_id,
      email,
      role,
      permissions,
      blocked,
      updated_at
    )
    values (
      workshop_uuid,
      clean_email,
      normalized_role,
      coalesce(member_permissions, '{}'::jsonb),
      coalesce(member_blocked, false),
      now()
    )
    on conflict (workshop_id, email) do update
    set role = excluded.role,
        permissions = excluded.permissions,
        blocked = excluded.blocked,
        updated_at = now();

    return true;
  end if;

  normalized_role := coalesce(nullif(trim(member_role), ''), 'worker');
  if normalized_role not in ('owner', 'manager', 'co_manager', 'admin', 'worker') then
    normalized_role := 'worker';
  end if;

  insert into public.workshop_members (
    workshop_id,
    user_id,
    role,
    permissions,
    blocked,
    updated_at
  )
  values (
    workshop_uuid,
    target_user_id,
    normalized_role,
    coalesce(member_permissions, '{}'::jsonb),
    coalesce(member_blocked, false),
    now()
  )
  on conflict (workshop_id, user_id) do update
  set role = excluded.role,
      permissions = excluded.permissions,
      blocked = excluded.blocked,
      updated_at = now();

  return true;
end;
$$;

grant execute on function public.update_workshop_member_permissions(text, text, text, jsonb, boolean) to authenticated;

create or replace function public.list_workshop_members(target_code text)
returns table (
  user_id uuid,
  email text,
  role text,
  permissions jsonb,
  blocked boolean,
  is_pending boolean,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  clean_code text;
  workshop_uuid uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  clean_code := nullif(trim(coalesce(target_code, '')), '');
  if clean_code is null then
    clean_code := auth.uid()::text;
  end if;

  select id
  into workshop_uuid
  from public.workshops
  where code = clean_code or join_code = clean_code
  limit 1;

  if workshop_uuid is null then
    raise exception 'Workshop was not found';
  end if;

  if not (
    public.is_app_admin()
    or exists (
      select 1
      from public.workshop_members
      where workshop_id = workshop_uuid
        and user_id = auth.uid()
        and role in ('owner', 'manager', 'co_manager', 'admin')
    )
  ) then
    raise exception 'You cannot view workshop members';
  end if;

  return query
  select
    member.user_id,
    coalesce(member_user.email, '')::text as email,
    member.role,
    member.permissions,
    member.blocked,
    false as is_pending,
    member.updated_at
  from public.workshop_members member
  left join auth.users member_user on member_user.id = member.user_id
  where member.workshop_id = workshop_uuid
    and member.role <> 'owner'
    -- Old installations may have orphan rows if their FK was created before
    -- the cascade rule. Do not present such deleted Auth users as workers.
    and member_user.id is not null;

  return query
  select
    null::uuid as user_id,
    invite.email,
    invite.role,
    invite.permissions,
    invite.blocked,
    true as is_pending,
    invite.updated_at
  from public.workshop_member_invites invite
  where invite.workshop_id = workshop_uuid
    and not exists (
      select 1
      from auth.users invite_user
      join public.workshop_members member
        on member.workshop_id = invite.workshop_id
       and member.user_id = invite_user.id
      where lower(invite_user.email) = lower(invite.email)
    );
end;
$$;

grant execute on function public.list_workshop_members(text) to authenticated;

create or replace function public.list_admin_workshops()
returns table (
  workshop_id uuid,
  code text,
  name text,
  owner_uid uuid,
  owner_email text,
  status text,
  plan_type text,
  starts_at timestamptz,
  ends_at timestamptz,
  max_users integer,
  max_systems integer,
  max_profiles integer,
  member_count bigint
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
  select
    w.id,
    coalesce(w.join_code, w.code)::text,
    w.name,
    w.owner_uid,
    coalesce(owner_user.email, '')::text,
    coalesce(s.status, 'expired')::text,
    coalesce(s.plan_type, 'trial')::text,
    s.starts_at,
    s.ends_at,
    coalesce(s.max_users, 4),
    coalesce(s.max_systems, 999),
    coalesce(s.max_profiles, 999),
    (select count(*) from public.workshop_members m where m.workshop_id = w.id)
  from public.workshops w
  left join public.workshop_subscriptions s on s.workshop_id = w.id
  left join auth.users owner_user on owner_user.id = w.owner_uid
  order by w.created_at desc;
end;
$$;

grant execute on function public.list_admin_workshops() to authenticated;

create table if not exists public.workshop_sync_rows (
  workshop_id uuid not null references public.workshops(id) on delete cascade,
  table_name text not null,
  row_id text not null,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  device_id text not null default '',
  revision bigint not null default 1,
  primary key (workshop_id, table_name, row_id)
);

create index if not exists workshop_sync_rows_updated_idx
on public.workshop_sync_rows (workshop_id, updated_at);

create index if not exists workshop_sync_rows_table_updated_idx
on public.workshop_sync_rows (workshop_id, table_name, updated_at);

alter table public.app_admins enable row level security;
alter table public.catalog_manifest enable row level security;
alter table public.catalog_chunks enable row level security;
alter table public.workshops enable row level security;
alter table public.workshop_members enable row level security;
alter table public.workshop_member_invites enable row level security;
alter table public.workshop_sync_rows enable row level security;

-- The worker join code belongs to the shared workshop identity. Publish code
-- changes so already-open devices refresh their local copy immediately.
do $$
begin
  alter publication supabase_realtime add table public.workshops;
exception
  when duplicate_object then null;
  when undefined_object then null;
end
$$;

do $$
begin
  alter publication supabase_realtime add table public.workshop_members;
exception
  when duplicate_object then null;
  when undefined_object then null;
end
$$;

do $$
begin
  alter publication supabase_realtime add table public.catalog_manifest;
exception
  when duplicate_object then null;
  when undefined_object then null;
end
$$;

drop policy if exists workshop_subscriptions_read_members
on public.workshop_subscriptions;
create policy workshop_subscriptions_read_members
on public.workshop_subscriptions
for select to authenticated
using (public.is_workshop_member(workshop_id));

-- Broadcast every workshop row/profile change so connected phones and the
-- Windows client update immediately. The client still keeps incremental
-- downloads on app resume as a recovery path if a Realtime connection is
-- interrupted; it does not poll continuously while the app is idle.
do $$
begin
  alter publication supabase_realtime add table public.workshop_sync_rows;
exception
  when duplicate_object then null;
  when undefined_object then null;
end
$$;

do $$
begin
  alter publication supabase_realtime add table public.workshop_subscriptions;
exception
  when duplicate_object then null;
  when undefined_object then null;
end
$$;

drop policy if exists "app admins read own row" on public.app_admins;
drop policy if exists "app admins manage admins" on public.app_admins;
drop policy if exists "app admins insert app admin" on public.app_admins;
drop policy if exists "app admins update app admin" on public.app_admins;
drop policy if exists "app admins delete app admin" on public.app_admins;
drop policy if exists "catalog manifest read authenticated" on public.catalog_manifest;
drop policy if exists "catalog manifest write app admin" on public.catalog_manifest;
drop policy if exists "catalog manifest insert app admin" on public.catalog_manifest;
drop policy if exists "catalog manifest update app admin" on public.catalog_manifest;
drop policy if exists "catalog manifest delete app admin" on public.catalog_manifest;
drop policy if exists "catalog chunks read authenticated" on public.catalog_chunks;
drop policy if exists "catalog chunks write app admin" on public.catalog_chunks;
drop policy if exists "catalog chunks delete app admin" on public.catalog_chunks;
drop policy if exists "workshops read members" on public.workshops;
drop policy if exists "workshops write app admin" on public.workshops;
drop policy if exists "workshops insert app admin" on public.workshops;
drop policy if exists "workshops update app admin" on public.workshops;
drop policy if exists "workshops delete app admin" on public.workshops;
drop policy if exists "workshop members read own or admin" on public.workshop_members;
drop policy if exists "workshop members write app admin" on public.workshop_members;
drop policy if exists "workshop members insert app admin" on public.workshop_members;
drop policy if exists "workshop members update app admin" on public.workshop_members;
drop policy if exists "workshop members delete app admin" on public.workshop_members;
drop policy if exists "workshop member invites read managers" on public.workshop_member_invites;
drop policy if exists "workshop member invites insert managers" on public.workshop_member_invites;
drop policy if exists "workshop member invites update managers" on public.workshop_member_invites;
drop policy if exists "workshop member invites delete managers" on public.workshop_member_invites;
drop policy if exists "workshop rows read members" on public.workshop_sync_rows;
drop policy if exists "workshop rows insert members" on public.workshop_sync_rows;
drop policy if exists "workshop rows update members" on public.workshop_sync_rows;
drop policy if exists "workshop rows delete members" on public.workshop_sync_rows;
drop policy if exists app_admins_read_own_row on public.app_admins;
drop policy if exists app_admins_insert_app_admin on public.app_admins;
drop policy if exists app_admins_update_app_admin on public.app_admins;
drop policy if exists app_admins_delete_app_admin on public.app_admins;
drop policy if exists catalog_manifest_read_authenticated on public.catalog_manifest;
drop policy if exists catalog_manifest_insert_app_admin on public.catalog_manifest;
drop policy if exists catalog_manifest_update_app_admin on public.catalog_manifest;
drop policy if exists catalog_manifest_delete_app_admin on public.catalog_manifest;
drop policy if exists catalog_chunks_read_authenticated on public.catalog_chunks;
drop policy if exists catalog_chunks_insert_app_admin on public.catalog_chunks;
drop policy if exists catalog_chunks_delete_app_admin on public.catalog_chunks;
drop policy if exists workshops_read_members on public.workshops;
drop policy if exists workshops_insert_app_admin on public.workshops;
drop policy if exists workshops_update_app_admin on public.workshops;
drop policy if exists workshops_delete_app_admin on public.workshops;
drop policy if exists workshop_members_read_own_or_admin on public.workshop_members;
drop policy if exists workshop_members_insert_app_admin on public.workshop_members;
drop policy if exists workshop_members_update_app_admin on public.workshop_members;
drop policy if exists workshop_members_delete_app_admin on public.workshop_members;
drop policy if exists workshop_member_invites_read_managers on public.workshop_member_invites;
drop policy if exists workshop_member_invites_insert_managers on public.workshop_member_invites;
drop policy if exists workshop_member_invites_update_managers on public.workshop_member_invites;
drop policy if exists workshop_member_invites_delete_managers on public.workshop_member_invites;
drop policy if exists workshop_rows_read_members on public.workshop_sync_rows;
drop policy if exists workshop_rows_insert_members on public.workshop_sync_rows;
drop policy if exists workshop_rows_update_members on public.workshop_sync_rows;
drop policy if exists workshop_rows_delete_members on public.workshop_sync_rows;

do $$
begin
  execute $policy$
    create policy app_admins_read_own_row
    on public.app_admins
    for select
    to authenticated
    using (user_id = (select auth.uid()) or (select public.is_app_admin()))
  $policy$;

  execute $policy$
    create policy app_admins_insert_app_admin
    on public.app_admins
    for insert
    to authenticated
    with check ((select public.is_app_admin()))
  $policy$;

  execute $policy$
    create policy app_admins_update_app_admin
    on public.app_admins
    for update
    to authenticated
    using ((select public.is_app_admin()))
    with check ((select public.is_app_admin()))
  $policy$;

  execute $policy$
    create policy app_admins_delete_app_admin
    on public.app_admins
    for delete
    to authenticated
    using ((select public.is_app_admin()))
  $policy$;

  execute $policy$
    create policy catalog_manifest_read_authenticated
    on public.catalog_manifest
    for select
    to authenticated
    using (true)
  $policy$;

  execute $policy$
    create policy catalog_manifest_insert_app_admin
    on public.catalog_manifest
    for insert
    to authenticated
    with check ((select public.is_app_admin()))
  $policy$;

  execute $policy$
    create policy catalog_manifest_update_app_admin
    on public.catalog_manifest
    for update
    to authenticated
    using ((select public.is_app_admin()))
    with check ((select public.is_app_admin()))
  $policy$;

  execute $policy$
    create policy catalog_manifest_delete_app_admin
    on public.catalog_manifest
    for delete
    to authenticated
    using ((select public.is_app_admin()))
  $policy$;

  execute $policy$
    create policy catalog_chunks_read_authenticated
    on public.catalog_chunks
    for select
    to authenticated
    using (true)
  $policy$;

  execute $policy$
    create policy catalog_chunks_insert_app_admin
    on public.catalog_chunks
    for insert
    to authenticated
    with check ((select public.is_app_admin()))
  $policy$;

  execute $policy$
    create policy catalog_chunks_delete_app_admin
    on public.catalog_chunks
    for delete
    to authenticated
    using ((select public.is_app_admin()))
  $policy$;

  execute $policy$
    create policy workshops_read_members
    on public.workshops
    for select
    to authenticated
    using (public.is_workshop_member(id))
  $policy$;

  execute $policy$
    create policy workshops_insert_app_admin
    on public.workshops
    for insert
    to authenticated
    with check ((select public.is_app_admin()))
  $policy$;

  execute $policy$
    create policy workshops_update_app_admin
    on public.workshops
    for update
    to authenticated
    using ((select public.is_app_admin()))
    with check ((select public.is_app_admin()))
  $policy$;

  execute $policy$
    create policy workshops_delete_app_admin
    on public.workshops
    for delete
    to authenticated
    using ((select public.is_app_admin()))
  $policy$;

  execute $policy$
    create policy workshop_members_read_own_or_admin
    on public.workshop_members
    for select
    to authenticated
    using (user_id = (select auth.uid()) or (select public.is_app_admin()))
  $policy$;

  execute $policy$
    create policy workshop_members_insert_app_admin
    on public.workshop_members
    for insert
    to authenticated
    with check ((select public.is_app_admin()))
  $policy$;

  execute $policy$
    create policy workshop_members_update_app_admin
    on public.workshop_members
    for update
    to authenticated
    using ((select public.is_app_admin()))
    with check ((select public.is_app_admin()))
  $policy$;

  execute $policy$
    create policy workshop_members_delete_app_admin
    on public.workshop_members
    for delete
    to authenticated
    using ((select public.is_app_admin()))
  $policy$;

  execute $policy$
    create policy workshop_rows_read_members
    on public.workshop_sync_rows
    for select
    to authenticated
    using (
      (select public.is_app_admin())
      or workshop_id in (
        select m.workshop_id
        from public.workshop_members m
        where m.user_id = (select auth.uid())
      )
    )
  $policy$;

  execute $policy$
    create policy workshop_rows_insert_members
    on public.workshop_sync_rows
    for insert
    to authenticated
    with check (
      (select public.is_app_admin())
      or workshop_id in (
        select m.workshop_id
        from public.workshop_members m
        where m.user_id = (select auth.uid())
      )
    )
  $policy$;

  execute $policy$
    create policy workshop_rows_update_members
    on public.workshop_sync_rows
    for update
    to authenticated
    using (
      (select public.is_app_admin())
      or workshop_id in (
        select m.workshop_id
        from public.workshop_members m
        where m.user_id = (select auth.uid())
      )
    )
    with check (
      (select public.is_app_admin())
      or workshop_id in (
        select m.workshop_id
        from public.workshop_members m
        where m.user_id = (select auth.uid())
      )
    )
  $policy$;

  execute $policy$
    create policy workshop_rows_delete_members
    on public.workshop_sync_rows
    for delete
    to authenticated
    using (
      (select public.is_app_admin())
      or workshop_id in (
        select m.workshop_id
        from public.workshop_members m
        where m.user_id = (select auth.uid())
      )
    )
  $policy$;
end
$$;
