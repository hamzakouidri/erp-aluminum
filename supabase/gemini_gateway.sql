-- Gemini gateway quota ledger. Apply this before deploying the Edge Function.
-- Only the Edge Function's service-role client calls the RPC; users cannot
-- read or alter usage rows directly.

create table if not exists public.ai_request_windows (
  user_id uuid primary key references auth.users(id) on delete cascade,
  minute_window_started_at timestamptz not null default date_trunc('minute', now()),
  minute_requests integer not null default 0 check (minute_requests >= 0),
  day_window_started_on date not null default current_date,
  day_requests integer not null default 0 check (day_requests >= 0),
  updated_at timestamptz not null default now()
);

alter table public.ai_request_windows enable row level security;
revoke all on public.ai_request_windows from anon, authenticated;

create or replace function public.consume_gemini_request(
  p_user_id uuid,
  p_minute_limit integer default 12,
  p_day_limit integer default 600
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  permitted boolean := false;
begin
  if p_user_id is null or p_minute_limit < 1 or p_day_limit < 1 then
    return false;
  end if;

  insert into public.ai_request_windows (
    user_id,
    minute_window_started_at,
    minute_requests,
    day_window_started_on,
    day_requests,
    updated_at
  )
  values (p_user_id, date_trunc('minute', now()), 1, current_date, 1, now())
  on conflict (user_id) do update
  set
    minute_window_started_at = case
      when ai_request_windows.minute_window_started_at < date_trunc('minute', now())
        then date_trunc('minute', now())
      else ai_request_windows.minute_window_started_at
    end,
    minute_requests = case
      when ai_request_windows.minute_window_started_at < date_trunc('minute', now())
        then 1
      else ai_request_windows.minute_requests + 1
    end,
    day_window_started_on = case
      when ai_request_windows.day_window_started_on < current_date then current_date
      else ai_request_windows.day_window_started_on
    end,
    day_requests = case
      when ai_request_windows.day_window_started_on < current_date then 1
      else ai_request_windows.day_requests + 1
    end,
    updated_at = now()
  where
    (case
      when ai_request_windows.minute_window_started_at < date_trunc('minute', now()) then 0
      else ai_request_windows.minute_requests
    end) < p_minute_limit
    and
    (case
      when ai_request_windows.day_window_started_on < current_date then 0
      else ai_request_windows.day_requests
    end) < p_day_limit
  returning true into permitted;

  return coalesce(permitted, false);
end;
$$;

revoke all on function public.consume_gemini_request(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_gemini_request(uuid, integer, integer)
  to service_role;
