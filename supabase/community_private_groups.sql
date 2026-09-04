-- Private chats and group chats for Notebook Tutor
-- Run this entire file once in Supabase Dashboard > SQL Editor.

alter table public.community_rooms
  add column if not exists room_type text not null default 'public',
  add column if not exists created_by uuid references auth.users(id)
    on delete set null,
  add column if not exists direct_key text;

alter table public.community_rooms
  drop constraint if exists community_rooms_name_key;

alter table public.community_rooms
  drop constraint if exists community_rooms_room_type_check;
alter table public.community_rooms
  add constraint community_rooms_room_type_check
  check (room_type in ('public', 'direct', 'group'));

create unique index if not exists community_rooms_direct_key_idx
  on public.community_rooms(direct_key)
  where direct_key is not null;

create table if not exists public.community_room_members (
  room_id uuid not null references public.community_rooms(id)
    on delete cascade,
  user_id uuid not null references auth.users(id)
    on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

create index if not exists community_room_members_user_idx
  on public.community_room_members(user_id, joined_at desc);

alter table public.community_room_members enable row level security;

create or replace function public.can_access_community_room(target_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.community_rooms room
    where room.id = target_room_id
      and (
        room.room_type = 'public'
        or exists (
          select 1
          from public.community_room_members member
          where member.room_id = room.id
            and member.user_id = (select auth.uid())
        )
      )
  );
$$;

revoke all on function public.can_access_community_room(uuid) from public;
grant execute on function public.can_access_community_room(uuid)
  to authenticated;

-- Replace old permissive room/message policies with membership-aware policies.
do $$
declare
  policy_row record;
begin
  for policy_row in
    select tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'community_rooms',
        'community_room_members',
        'community_messages'
      )
  loop
    execute format(
      'drop policy if exists %I on public.%I',
      policy_row.policyname,
      policy_row.tablename
    );
  end loop;
end;
$$;

create policy "Users can read accessible community rooms"
  on public.community_rooms
  for select
  to authenticated
  using (public.can_access_community_room(id));

create policy "Creators can update their group rooms"
  on public.community_rooms
  for update
  to authenticated
  using (
    room_type = 'group'
    and created_by = (select auth.uid())
  )
  with check (
    room_type = 'group'
    and created_by = (select auth.uid())
  );

create policy "Creators can delete their group rooms"
  on public.community_rooms
  for delete
  to authenticated
  using (
    room_type = 'group'
    and created_by = (select auth.uid())
  );

create policy "Members can read accessible room membership"
  on public.community_room_members
  for select
  to authenticated
  using (public.can_access_community_room(room_id));

create policy "Users can read accessible room messages"
  on public.community_messages
  for select
  to authenticated
  using (public.can_access_community_room(room_id));

create policy "Users can send to accessible rooms"
  on public.community_messages
  for insert
  to authenticated
  with check (
    sender_id = (select auth.uid())
    and public.can_access_community_room(room_id)
  );

create policy "Users can delete their own messages"
  on public.community_messages
  for delete
  to authenticated
  using (sender_id = (select auth.uid()));

grant select on public.community_rooms to authenticated;
grant select on public.community_room_members to authenticated;
grant select, insert, delete on public.community_messages to authenticated;

create or replace function public.create_direct_chat(other_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := (select auth.uid());
  conversation_key text;
  result_room_id uuid;
begin
  if caller_id is null then
    raise exception 'You must be signed in.';
  end if;
  if other_user_id is null or other_user_id = caller_id then
    raise exception 'Choose another community user.';
  end if;
  if not exists (
    select 1 from public.community_profiles where id = other_user_id
  ) then
    raise exception 'That community user does not exist.';
  end if;

  conversation_key := least(caller_id::text, other_user_id::text)
    || ':' || greatest(caller_id::text, other_user_id::text);

  select id into result_room_id
  from public.community_rooms
  where direct_key = conversation_key;

  if result_room_id is null then
    begin
      insert into public.community_rooms (
        name,
        room_type,
        created_by,
        direct_key
      ) values (
        'Private chat',
        'direct',
        caller_id,
        conversation_key
      )
      returning id into result_room_id;
    exception when unique_violation then
      select id into result_room_id
      from public.community_rooms
      where direct_key = conversation_key;
    end;
  end if;

  insert into public.community_room_members(room_id, user_id)
  values
    (result_room_id, caller_id),
    (result_room_id, other_user_id)
  on conflict do nothing;

  return result_room_id;
end;
$$;

revoke all on function public.create_direct_chat(uuid) from public;
grant execute on function public.create_direct_chat(uuid) to authenticated;

create or replace function public.create_group_chat(
  group_name text,
  member_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := (select auth.uid());
  result_room_id uuid;
begin
  if caller_id is null then
    raise exception 'You must be signed in.';
  end if;
  if char_length(trim(group_name)) not between 1 and 60 then
    raise exception 'Group name must contain 1 to 60 characters.';
  end if;
  if coalesce(array_length(member_ids, 1), 0) < 1 then
    raise exception 'Choose at least one group member.';
  end if;

  insert into public.community_rooms(name, room_type, created_by)
  values (trim(group_name), 'group', caller_id)
  returning id into result_room_id;

  insert into public.community_room_members(room_id, user_id)
  values (result_room_id, caller_id)
  on conflict do nothing;

  insert into public.community_room_members(room_id, user_id)
  select result_room_id, profile.id
  from public.community_profiles profile
  where profile.id = any(member_ids)
    and profile.id <> caller_id
  on conflict do nothing;

  return result_room_id;
end;
$$;

revoke all on function public.create_group_chat(text, uuid[]) from public;
grant execute on function public.create_group_chat(text, uuid[])
  to authenticated;

-- Keep community images private to public-room visitors or private-room members.
drop policy if exists "Community users can read uploaded files"
  on storage.objects;
drop policy if exists "Community users can upload files"
  on storage.objects;
drop policy if exists "Community users can delete own files"
  on storage.objects;
drop policy if exists "Community users can update own files"
  on storage.objects;

create policy "Community users can read accessible images"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'community-uploads'
    and (
      array_length(storage.foldername(name), 1) = 1
      or public.can_access_community_room(
        ((storage.foldername(name))[2])::uuid
      )
    )
  );

create policy "Community users can upload accessible images"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'community-uploads'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and public.can_access_community_room(
      ((storage.foldername(name))[2])::uuid
    )
  );

create policy "Community users can update own images"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'community-uploads'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'community-uploads'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Community users can delete own images"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'community-uploads'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Realtime for newly added membership rows (messages were enabled earlier).
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'community_room_members'
  ) then
    alter publication supabase_realtime
      add table public.community_room_members;
  end if;
end;
$$;
