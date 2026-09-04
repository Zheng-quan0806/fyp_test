-- Notebook Tutor GPT cloud history
-- Run this entire file once in Supabase Dashboard > SQL Editor.

create table if not exists public.gpt_chat_threads (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'New chat',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create table if not exists public.gpt_chat_messages (
  id text primary key,
  thread_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null,
  is_user boolean not null,
  created_at timestamptz not null default now(),
  image_path text,
  image_mime_type text,
  constraint gpt_chat_messages_thread_owner_fk
    foreign key (thread_id, user_id)
    references public.gpt_chat_threads(id, user_id)
    on delete cascade
);

create index if not exists gpt_chat_threads_user_updated_idx
  on public.gpt_chat_threads(user_id, updated_at desc);

create index if not exists gpt_chat_messages_thread_created_idx
  on public.gpt_chat_messages(thread_id, created_at);

alter table public.gpt_chat_threads enable row level security;
alter table public.gpt_chat_messages enable row level security;

drop policy if exists "GPT users can read own threads"
  on public.gpt_chat_threads;
create policy "GPT users can read own threads"
  on public.gpt_chat_threads
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "GPT users can create own threads"
  on public.gpt_chat_threads;
create policy "GPT users can create own threads"
  on public.gpt_chat_threads
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "GPT users can update own threads"
  on public.gpt_chat_threads;
create policy "GPT users can update own threads"
  on public.gpt_chat_threads
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "GPT users can delete own threads"
  on public.gpt_chat_threads;
create policy "GPT users can delete own threads"
  on public.gpt_chat_threads
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "GPT users can read own messages"
  on public.gpt_chat_messages;
create policy "GPT users can read own messages"
  on public.gpt_chat_messages
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "GPT users can create own messages"
  on public.gpt_chat_messages;
create policy "GPT users can create own messages"
  on public.gpt_chat_messages
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "GPT users can update own messages"
  on public.gpt_chat_messages;
create policy "GPT users can update own messages"
  on public.gpt_chat_messages
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "GPT users can delete own messages"
  on public.gpt_chat_messages;
create policy "GPT users can delete own messages"
  on public.gpt_chat_messages
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

grant select, insert, update, delete
  on public.gpt_chat_threads, public.gpt_chat_messages
  to authenticated;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'gpt-uploads',
  'gpt-uploads',
  false,
  6291456,
  array['image/png', 'image/jpeg', 'image/webp', 'image/gif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "GPT users can read own images" on storage.objects;
create policy "GPT users can read own images"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'gpt-uploads'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "GPT users can upload own images" on storage.objects;
create policy "GPT users can upload own images"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'gpt-uploads'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "GPT users can update own images" on storage.objects;
create policy "GPT users can update own images"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'gpt-uploads'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'gpt-uploads'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "GPT users can delete own images" on storage.objects;
create policy "GPT users can delete own images"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'gpt-uploads'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
