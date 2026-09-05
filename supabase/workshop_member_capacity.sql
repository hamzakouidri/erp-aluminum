-- Apply once. Limits are subsequently managed from the application.
create or replace function public.enforce_workshop_member_capacity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid;
  allowed integer;
  occupied bigint;
begin
  -- Serialize joins for the same workshop before counting available seats.
  select owner_uid into owner_id from public.workshops
  where id = new.workshop_id for update;

  -- Permission updates/upserts for existing members do not consume a seat.
  if exists (select 1 from public.workshop_members
      where workshop_id = new.workshop_id and user_id = new.user_id) then
    return new;
  end if;
  select max_users into allowed from public.workshop_subscriptions
  where workshop_id = new.workshop_id;
  allowed := coalesce(allowed, 4);
  -- Reserve the owner's seat even for legacy workshops missing its member row.
  select count(*) into occupied from public.workshop_members
  where workshop_id = new.workshop_id and user_id <> owner_id;
  if new.user_id <> owner_id and occupied + 1 >= allowed then
    raise exception 'WORKSHOP_USER_LIMIT_REACHED';
  end if;
  return new;
end;
$$;

drop trigger if exists workshop_members_enforce_capacity on public.workshop_members;
create trigger workshop_members_enforce_capacity
before insert or update of workshop_id, user_id on public.workshop_members
for each row execute function public.enforce_workshop_member_capacity();
