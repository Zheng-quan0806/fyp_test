-- Run this once in Supabase Dashboard > SQL Editor.
-- Calendar tasks remain available locally even before this script is run.

create table if not exists public.calendar_tasks (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 200),
  details text not null default '',
  task_date date not null,
  task_time time,
  is_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists calendar_tasks_user_date_idx
  on public.calendar_tasks (user_id, task_date, task_time);

alter table public.calendar_tasks enable row level security;

drop policy if exists "Users can read their calendar tasks"
  on public.calendar_tasks;
create policy "Users can read their calendar tasks"
  on public.calendar_tasks
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can create their calendar tasks"
  on public.calendar_tasks;
create policy "Users can create their calendar tasks"
  on public.calendar_tasks
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their calendar tasks"
  on public.calendar_tasks;
create policy "Users can update their calendar tasks"
  on public.calendar_tasks
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete their calendar tasks"
  on public.calendar_tasks;
create policy "Users can delete their calendar tasks"
  on public.calendar_tasks
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

grant select, insert, update, delete
  on table public.calendar_tasks
  to authenticated;
