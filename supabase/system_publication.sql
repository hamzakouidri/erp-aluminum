-- Publication of work systems and profile systems (نشر الأنظمة).
--
-- The application owner hides a system that is still being developed; it
-- then stays off for every user of every workshop, whatever their workshop
-- selected, until the owner publishes it. Every signed-in user reads the
-- list; only an application admin (public.is_app_admin(), see
-- catalog_sync.sql) can change it.
--
-- system_key is 'mode:<id>' for a work system (sliding, french, mixed, ...)
-- or 'profile:<code or lower-case name>' for a profile system. A system
-- without a row is published. Safe to run more than once.

create table if not exists public.app_system_publication (
  system_key text primary key,
  published boolean not null default true,
  label text not null default '',
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

alter table public.app_system_publication enable row level security;

drop policy if exists "signed in users read system publication"
  on public.app_system_publication;
create policy "signed in users read system publication"
  on public.app_system_publication
  for select
  to authenticated
  using (true);

drop policy if exists "app admins publish systems"
  on public.app_system_publication;
create policy "app admins publish systems"
  on public.app_system_publication
  for all
  to authenticated
  using (public.is_app_admin())
  with check (public.is_app_admin());

grant select, insert, update, delete
  on public.app_system_publication to authenticated;
