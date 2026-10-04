-- Evaluate the application-admin lookup once per SQL statement instead of
-- once for every row visited by an RLS policy. This preserves the same access
-- rules while avoiding thousands of scans of the one-row app_admins table.

alter policy app_admins_read_own_row
on public.app_admins
using (
  user_id = (select auth.uid())
  or (select public.is_app_admin())
);

alter policy workshop_members_read_own_or_admin
on public.workshop_members
using (
  user_id = (select auth.uid())
  or (select public.is_app_admin())
);

alter policy workshop_rows_read_members
on public.workshop_sync_rows
using (
  (select public.is_app_admin())
  or workshop_id in (
    select m.workshop_id
    from public.workshop_members m
    where m.user_id = (select auth.uid())
  )
);

alter policy workshop_rows_insert_members
on public.workshop_sync_rows
with check (
  (select public.is_app_admin())
  or workshop_id in (
    select m.workshop_id
    from public.workshop_members m
    where m.user_id = (select auth.uid())
  )
);

alter policy workshop_rows_update_members
on public.workshop_sync_rows
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
);

alter policy workshop_rows_delete_members
on public.workshop_sync_rows
using (
  (select public.is_app_admin())
  or workshop_id in (
    select m.workshop_id
    from public.workshop_members m
    where m.user_id = (select auth.uid())
  )
);

-- These tables are touched less frequently, but using an init-plan here
-- prevents the same regression during bulk catalogue or workshop operations.
alter policy catalog_manifest_insert_app_admin
on public.catalog_manifest
with check ((select public.is_app_admin()));

alter policy catalog_manifest_update_app_admin
on public.catalog_manifest
using ((select public.is_app_admin()))
with check ((select public.is_app_admin()));

alter policy catalog_manifest_delete_app_admin
on public.catalog_manifest
using ((select public.is_app_admin()));

alter policy catalog_chunks_insert_app_admin
on public.catalog_chunks
with check ((select public.is_app_admin()));

alter policy catalog_chunks_delete_app_admin
on public.catalog_chunks
using ((select public.is_app_admin()));

alter policy workshops_insert_app_admin
on public.workshops
with check ((select public.is_app_admin()));

alter policy workshops_update_app_admin
on public.workshops
using ((select public.is_app_admin()))
with check ((select public.is_app_admin()));

alter policy workshops_delete_app_admin
on public.workshops
using ((select public.is_app_admin()));

alter policy workshop_members_insert_app_admin
on public.workshop_members
with check ((select public.is_app_admin()));

alter policy workshop_members_update_app_admin
on public.workshop_members
using ((select public.is_app_admin()))
with check ((select public.is_app_admin()));

alter policy workshop_members_delete_app_admin
on public.workshop_members
using ((select public.is_app_admin()));

notify pgrst, 'reload schema';
