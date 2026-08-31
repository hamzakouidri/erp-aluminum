-- Run this once in the Supabase SQL Editor.
-- The application-admin screen uses this RPC to load all workshops.
-- It is safe to run again because the function is replaced in place.

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

-- Ask PostgREST to refresh its RPC schema cache immediately.
notify pgrst, 'reload schema';
