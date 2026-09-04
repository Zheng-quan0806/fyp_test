-- ONE-TIME TEST/RECOVERY SCRIPT
-- Run this in Supabase Dashboard > SQL Editor only for the account you want
-- to restore. Replace YOUR_GOOGLE_EMAIL before running it.

do $$
declare
  v_user_id uuid;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  select id into v_user_id
  from auth.users
  where lower(email) = lower('YOUR_GOOGLE_EMAIL')
  limit 1;

  if v_user_id is null then
    raise exception 'No Supabase user found for that email address';
  end if;

  insert into public.study_daily_progress (
    user_id,
    study_date,
    active_seconds,
    completed_at,
    timezone,
    updated_at
  )
  values
    (v_user_id, v_today - 1, 300, now(), 'UTC+08:00', now()),
    (v_user_id, v_today, 300, now(), 'UTC+08:00', now())
  on conflict (user_id, study_date) do update
  set active_seconds = greatest(study_daily_progress.active_seconds, 300),
      completed_at = coalesce(study_daily_progress.completed_at, now()),
      timezone = 'UTC+08:00',
      updated_at = now();

  insert into public.study_streaks (
    user_id,
    current_streak,
    longest_streak,
    status,
    recovery_days,
    last_completed_date,
    updated_at
  )
  values (v_user_id, 2, 2, 'active', 0, v_today, now())
  on conflict (user_id) do update
  set current_streak = 2,
      longest_streak = greatest(study_streaks.longest_streak, 2),
      status = 'active',
      recovery_days = 0,
      last_completed_date = v_today,
      updated_at = now();
end;
$$;
