-- Daily active-study progress and streak state.
create table if not exists public.study_daily_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  study_date date not null,
  active_seconds integer not null default 0 check (active_seconds >= 0),
  completed_at timestamptz,
  timezone text not null default 'UTC',
  updated_at timestamptz not null default now(),
  primary key (user_id, study_date)
);

create table if not exists public.study_streaks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  current_streak integer not null default 0 check (current_streak >= 0),
  longest_streak integer not null default 0 check (longest_streak >= 0),
  status text not null default 'active' check (status in ('active', 'probation')),
  recovery_days integer not null default 0 check (recovery_days between 0 and 3),
  last_completed_date date,
  updated_at timestamptz not null default now()
);

-- Migrate recovery progress from the previous 3-day rule. Anyone who already
-- completed two recovery days has now satisfied the new 2-day rule.
update public.study_streaks
set status = 'active',
    current_streak = greatest(current_streak, 2),
    longest_streak = greatest(longest_streak, 2),
    recovery_days = 0,
    updated_at = now()
where status = 'probation' and recovery_days >= 2;

alter table public.study_streaks
  drop constraint if exists study_streaks_recovery_days_check;
alter table public.study_streaks
  add constraint study_streaks_recovery_days_check
  check (recovery_days between 0 and 2);

alter table public.study_daily_progress enable row level security;
alter table public.study_streaks enable row level security;

drop policy if exists "Users read own study progress" on public.study_daily_progress;
create policy "Users read own study progress"
on public.study_daily_progress for select to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users read own streak" on public.study_streaks;
create policy "Users read own streak"
on public.study_streaks for select to authenticated
using ((select auth.uid()) = user_id);

create or replace function public.record_study_time(
  p_seconds integer,
  p_study_date date,
  p_timezone text default 'UTC'
)
returns table (
  active_seconds integer,
  current_streak integer,
  longest_streak integer,
  status text,
  recovery_days integer,
  last_completed_date date
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_after integer;
  v_streak public.study_streaks%rowtype;
  v_consecutive boolean;
  v_gap integer;
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;
  if p_seconds < 1 or p_seconds > 300 then
    raise exception 'Study-time update must be between 1 and 300 seconds';
  end if;
  if p_study_date < current_date - 1 or p_study_date > current_date + 1 then
    raise exception 'Invalid study date';
  end if;

  insert into public.study_daily_progress
    (user_id, study_date, active_seconds, timezone)
  values (v_user, p_study_date, 0, left(coalesce(p_timezone, 'UTC'), 50))
  on conflict (user_id, study_date) do nothing;

  select d.active_seconds into v_after
  from public.study_daily_progress d
  where d.user_id = v_user and d.study_date = p_study_date
  for update;

  update public.study_daily_progress d
  set active_seconds = least(d.active_seconds + p_seconds, 86400),
      timezone = left(coalesce(p_timezone, 'UTC'), 50),
      updated_at = now()
  where d.user_id = v_user and d.study_date = p_study_date
  returning d.active_seconds into v_after;

  insert into public.study_streaks (user_id)
  values (v_user)
  on conflict (user_id) do nothing;

  select s.* into v_streak
  from public.study_streaks s
  where s.user_id = v_user
  for update;

  -- One missed calendar day starts probation. Two consecutive missed days
  -- permanently reset the old streak before today's progress is evaluated.
  if v_streak.last_completed_date is not null then
    v_gap := p_study_date - v_streak.last_completed_date;
    if v_gap >= 3 then
      v_streak.status := 'active';
      v_streak.current_streak := 0;
      v_streak.recovery_days := 0;
      v_streak.last_completed_date := null;
    elsif v_gap >= 2 then
      v_streak.status := 'probation';
      v_streak.current_streak := 0;
      v_streak.recovery_days := 0;
    end if;

    update public.study_streaks s
    set current_streak = v_streak.current_streak,
        status = v_streak.status,
        recovery_days = v_streak.recovery_days,
        last_completed_date = v_streak.last_completed_date,
        updated_at = now()
    where s.user_id = v_user;
  end if;

  -- Five-minute temporary testing goal. Change both 300 values to 1800 when
  -- the production goal returns to 30 minutes. The date guard prevents an
  -- already-earned day from being awarded again after that change.
  if v_after >= 300
     and v_streak.last_completed_date is distinct from p_study_date then
    v_consecutive := v_streak.last_completed_date = p_study_date - 1;

    if v_streak.last_completed_date is null then
      v_streak.status := 'active';
      v_streak.current_streak := 1;
      v_streak.recovery_days := 0;
    elsif v_streak.status = 'probation' or not v_consecutive then
      v_streak.status := 'probation';
      v_streak.current_streak := 0;
      if v_consecutive then
        v_streak.recovery_days := v_streak.recovery_days + 1;
      else
        v_streak.recovery_days := 1;
      end if;
      if v_streak.recovery_days >= 2 then
        v_streak.status := 'active';
        v_streak.current_streak := 2;
        v_streak.recovery_days := 0;
      end if;
    else
      v_streak.current_streak := v_streak.current_streak + 1;
    end if;

    v_streak.longest_streak := greatest(
      v_streak.longest_streak,
      v_streak.current_streak
    );
    v_streak.last_completed_date := p_study_date;

    update public.study_daily_progress d
    set completed_at = coalesce(d.completed_at, now())
    where d.user_id = v_user and d.study_date = p_study_date;

    update public.study_streaks s
    set current_streak = v_streak.current_streak,
        longest_streak = v_streak.longest_streak,
        status = v_streak.status,
        recovery_days = v_streak.recovery_days,
        last_completed_date = v_streak.last_completed_date,
        updated_at = now()
    where s.user_id = v_user;
  end if;

  return query
  select d.active_seconds, s.current_streak, s.longest_streak,
         s.status, s.recovery_days, s.last_completed_date
  from public.study_daily_progress d
  join public.study_streaks s on s.user_id = d.user_id
  where d.user_id = v_user and d.study_date = p_study_date;
end;
$$;

revoke all on function public.record_study_time(integer, date, text) from public;
grant execute on function public.record_study_time(integer, date, text) to authenticated;
