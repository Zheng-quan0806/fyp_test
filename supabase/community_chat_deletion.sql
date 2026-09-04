-- Per-user deletion for private and group conversations.
-- Run this entire file once in Supabase Dashboard > SQL Editor.

create table if not exists public.community_hidden_rooms (
  user_id uuid not null references auth.users(id) on delete cascade,
  room_id uuid not null references public.community_rooms(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key (user_id, room_id)
);

create index if not exists community_hidden_rooms_user_idx
  on public.community_hidden_rooms (user_id, hidden_at desc);

alter table public.community_hidden_rooms enable row level security;

drop policy if exists "Users can read their hidden community chats"
  on public.community_hidden_rooms;
create policy "Users can read their hidden community chats"
  on public.community_hidden_rooms
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can hide their community chats"
  on public.community_hidden_rooms;
create policy "Users can hide their community chats"
  on public.community_hidden_rooms
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their hidden community chats"
  on public.community_hidden_rooms;
create policy "Users can update their hidden community chats"
  on public.community_hidden_rooms
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can restore their hidden community chats"
  on public.community_hidden_rooms;
create policy "Users can restore their hidden community chats"
  on public.community_hidden_rooms
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

grant select, insert, update, delete
  on table public.community_hidden_rooms
  to authenticated;

-- A new incoming message makes a deleted conversation visible again.
create or replace function public.restore_hidden_chat_on_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.community_hidden_rooms
  where room_id = new.room_id
    and user_id <> new.sender_id;
  return new;
end;
$$;

revoke all on function public.restore_hidden_chat_on_message() from public;

drop trigger if exists restore_hidden_chat_on_message
  on public.community_messages;
create trigger restore_hidden_chat_on_message
  after insert on public.community_messages
  for each row
  execute function public.restore_hidden_chat_on_message();
