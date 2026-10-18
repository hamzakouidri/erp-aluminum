-- Daily AI request counts per user, written only by the gemini-proxy Edge
-- Function (service role). Users cannot read or change it. Safe to run more
-- than once.

create table if not exists public.ai_usage_daily (
  user_id uuid not null,
  day date not null,
  requests integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

alter table public.ai_usage_daily enable row level security;

drop policy if exists "app admins read ai usage" on public.ai_usage_daily;
create policy "app admins read ai usage"
  on public.ai_usage_daily
  for select
  to authenticated
  using (public.is_app_admin());
