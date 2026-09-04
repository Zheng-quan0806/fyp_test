-- Notebook notes and folders cloud storage
-- Run this entire file once in Supabase Dashboard > SQL Editor.

create table if not exists public.notebook_folders (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  color_hex text not null default '6C63FF',
  parent_folder_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (id, user_id)
);

create table if not exists public.notebook_notes (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  folder_id text,
  data_path text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (id, user_id)
);

create index if not exists notebook_folders_user_updated_idx
  on public.notebook_folders(user_id, updated_at desc);

create index if not exists notebook_notes_user_updated_idx
  on public.notebook_notes(user_id, updated_at desc);

alter table public.notebook_folders enable row level security;
alter table public.notebook_notes enable row level security;

drop policy if exists "Notebook users can read own folders"
  on public.notebook_folders;
create policy "Notebook users can read own folders"
  on public.notebook_folders
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Notebook users can create own folders"
  on public.notebook_folders;
create policy "Notebook users can create own folders"
  on public.notebook_folders
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Notebook users can update own folders"
  on public.notebook_folders;
create policy "Notebook users can update own folders"
  on public.notebook_folders
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Notebook users can delete own folders"
  on public.notebook_folders;
create policy "Notebook users can delete own folders"
  on public.notebook_folders
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Notebook users can read own notes"
  on public.notebook_notes;
create policy "Notebook users can read own notes"
  on public.notebook_notes
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Notebook users can create own notes"
  on public.notebook_notes;
create policy "Notebook users can create own notes"
  on public.notebook_notes
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Notebook users can update own notes"
  on public.notebook_notes;
create policy "Notebook users can update own notes"
  on public.notebook_notes
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Notebook users can delete own notes"
  on public.notebook_notes;
create policy "Notebook users can delete own notes"
  on public.notebook_notes
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

grant select, insert, update, delete
  on public.notebook_folders, public.notebook_notes
  to authenticated;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'note-data',
  'note-data',
  false,
  52428800,
  array['application/json']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Notebook users can read own note data"
  on storage.objects;
create policy "Notebook users can read own note data"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'note-data'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Notebook users can upload own note data"
  on storage.objects;
create policy "Notebook users can upload own note data"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'note-data'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Notebook users can update own note data"
  on storage.objects;
create policy "Notebook users can update own note data"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'note-data'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'note-data'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Notebook users can delete own note data"
  on storage.objects;
create policy "Notebook users can delete own note data"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'note-data'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
