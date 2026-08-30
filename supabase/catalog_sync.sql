create table if not exists public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

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
    where user_id = auth.uid()
  );
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
  name text not null default '',
  owner_uid uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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
        and user_id = auth.uid()
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
  workshop_was_created boolean := false;
  current_email text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  clean_code := nullif(trim(coalesce(target_code, '')), '');
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
  where code = clean_code
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
        raise exception 'You are not a member of this workshop';
      end if;
    end if;
  else
    insert into public.workshops (code, name, owner_uid)
    values (clean_code, clean_name, auth.uid())
    returning id into workshop_uuid;
    workshop_was_created := true;
  end if;

  if existing_workshop.owner_uid = auth.uid()
     or workshop_was_created
     or public.is_app_admin() then
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
  where code = clean_code
  limit 1;

  if workshop_uuid is null then
    workshop_uuid := public.ensure_my_workshop(clean_code, clean_code);
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
  where code = clean_code
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
    and member.role <> 'owner';

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

do $$
begin
  alter publication supabase_realtime add table public.workshop_members;
exception
  when duplicate_object then null;
  when undefined_object then null;
end
$$;

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
    using (user_id = auth.uid() or public.is_app_admin())
  $policy$;

  execute $policy$
    create policy app_admins_insert_app_admin
    on public.app_admins
    for insert
    to authenticated
    with check (public.is_app_admin())
  $policy$;

  execute $policy$
    create policy app_admins_update_app_admin
    on public.app_admins
    for update
    to authenticated
    using (public.is_app_admin())
    with check (public.is_app_admin())
  $policy$;

  execute $policy$
    create policy app_admins_delete_app_admin
    on public.app_admins
    for delete
    to authenticated
    using (public.is_app_admin())
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
    with check (public.is_app_admin())
  $policy$;

  execute $policy$
    create policy catalog_manifest_update_app_admin
    on public.catalog_manifest
    for update
    to authenticated
    using (public.is_app_admin())
    with check (public.is_app_admin())
  $policy$;

  execute $policy$
    create policy catalog_manifest_delete_app_admin
    on public.catalog_manifest
    for delete
    to authenticated
    using (public.is_app_admin())
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
    with check (public.is_app_admin())
  $policy$;

  execute $policy$
    create policy catalog_chunks_delete_app_admin
    on public.catalog_chunks
    for delete
    to authenticated
    using (public.is_app_admin())
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
    with check (public.is_app_admin())
  $policy$;

  execute $policy$
    create policy workshops_update_app_admin
    on public.workshops
    for update
    to authenticated
    using (public.is_app_admin())
    with check (public.is_app_admin())
  $policy$;

  execute $policy$
    create policy workshops_delete_app_admin
    on public.workshops
    for delete
    to authenticated
    using (public.is_app_admin())
  $policy$;

  execute $policy$
    create policy workshop_members_read_own_or_admin
    on public.workshop_members
    for select
    to authenticated
    using (user_id = auth.uid() or public.is_app_admin())
  $policy$;

  execute $policy$
    create policy workshop_members_insert_app_admin
    on public.workshop_members
    for insert
    to authenticated
    with check (public.is_app_admin())
  $policy$;

  execute $policy$
    create policy workshop_members_update_app_admin
    on public.workshop_members
    for update
    to authenticated
    using (public.is_app_admin())
    with check (public.is_app_admin())
  $policy$;

  execute $policy$
    create policy workshop_members_delete_app_admin
    on public.workshop_members
    for delete
    to authenticated
    using (public.is_app_admin())
  $policy$;

  execute $policy$
    create policy workshop_rows_read_members
    on public.workshop_sync_rows
    for select
    to authenticated
    using (public.is_workshop_member(workshop_id))
  $policy$;

  execute $policy$
    create policy workshop_rows_insert_members
    on public.workshop_sync_rows
    for insert
    to authenticated
    with check (public.is_workshop_member(workshop_id))
  $policy$;

  execute $policy$
    create policy workshop_rows_update_members
    on public.workshop_sync_rows
    for update
    to authenticated
    using (public.is_workshop_member(workshop_id))
    with check (public.is_workshop_member(workshop_id))
  $policy$;

  execute $policy$
    create policy workshop_rows_delete_members
    on public.workshop_sync_rows
    for delete
    to authenticated
    using (public.is_workshop_member(workshop_id))
  $policy$;
end
$$;
