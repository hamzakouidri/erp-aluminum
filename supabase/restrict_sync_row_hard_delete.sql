-- Only the application admin may hard-delete workshop_sync_rows.
--
-- The app never hard-deletes a sync row: a deletion is an upsert that sets
-- deleted_at, so every device learns it and sync_deletion_guard.sql can hold
-- a burst back. The policy workshop_rows_delete_members still let any member
-- (a worker phone, an old build, any client holding a session) remove rows
-- for good: no tombstone, no guard, and no copy left on the server.
--
-- Run after optimize_app_admin_rls.sql. Safe to run more than once.

alter policy workshop_rows_delete_members
on public.workshop_sync_rows
using ((select public.is_app_admin()));
