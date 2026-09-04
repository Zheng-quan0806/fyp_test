-- Friend requests and friend-only conversations for Notebook Tutor.
-- Run this after community_private_groups.sql.

alter table public.community_profiles
  add column if not exists username text;

update public.community_profiles
set username = 'user_' || substring(replace(id::text, '-', ''), 1, 8)
where username is null or trim(username) = '';

alter table public.community_profiles
  alter column username set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'community_profiles_username_check'
  ) then
    alter table public.community_profiles
      add constraint community_profiles_username_check
      check (username ~ '^[a-z0-9_]{3,24}$');
  end if;
end;
$$;

create unique index if not exists community_profiles_username_idx
  on public.community_profiles (lower(username));

create table if not exists public.community_friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  addressee_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (requester_id <> addressee_id)
);

create unique index if not exists community_friendships_pair_idx
  on public.community_friendships (
    least(requester_id, addressee_id),
    greatest(requester_id, addressee_id)
  );

create index if not exists community_friendships_requester_idx
  on public.community_friendships(requester_id, status);
create index if not exists community_friendships_addressee_idx
  on public.community_friendships(addressee_id, status);

alter table public.community_friendships enable row level security;

drop policy if exists "Users can read their friendships"
  on public.community_friendships;
create policy "Users can read their friendships"
on public.community_friendships for select to authenticated
using (
  requester_id = (select auth.uid())
  or addressee_id = (select auth.uid())
);

grant select on public.community_friendships to authenticated;

create or replace function public.set_community_username(new_username text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  normalized text := lower(trim(new_username));
begin
  if caller_id is null then raise exception 'You must be signed in.'; end if;
  if normalized !~ '^[a-z0-9_]{3,24}$' then
    raise exception 'Username must be 3-24 characters using letters, numbers, or underscore.';
  end if;
  if exists (
    select 1 from public.community_profiles
    where lower(username) = normalized and id <> caller_id
  ) then
    raise exception 'That username is already taken.';
  end if;
  update public.community_profiles set username = normalized
  where id = caller_id;
  return normalized;
end;
$$;

create or replace function public.search_community_profiles(search_text text)
returns table (id uuid, display_name text, username text)
language sql
stable
security definer
set search_path = public
as $$
  select profile.id, profile.display_name, profile.username
  from public.community_profiles profile
  where auth.uid() is not null
    and profile.id <> auth.uid()
    and trim(search_text) <> ''
    and (
      profile.username ilike '%' || trim(search_text) || '%'
      or profile.display_name ilike '%' || trim(search_text) || '%'
    )
  order by
    case when lower(profile.username) = lower(trim(search_text)) then 0 else 1 end,
    profile.display_name
  limit 20;
$$;

create or replace function public.send_community_friend_request(other_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  result_id uuid;
begin
  if caller_id is null then raise exception 'You must be signed in.'; end if;
  if other_user_id is null or other_user_id = caller_id then
    raise exception 'Choose another community user.';
  end if;
  if not exists (select 1 from public.community_profiles where id = other_user_id) then
    raise exception 'That community user does not exist.';
  end if;

  select id into result_id
  from public.community_friendships
  where least(requester_id, addressee_id) = least(caller_id, other_user_id)
    and greatest(requester_id, addressee_id) = greatest(caller_id, other_user_id);

  if result_id is not null then
    raise exception 'A friendship or pending request already exists.';
  end if;

  insert into public.community_friendships(requester_id, addressee_id)
  values (caller_id, other_user_id)
  returning id into result_id;
  return result_id;
end;
$$;

create or replace function public.respond_community_friend_request(
  friendship_id uuid,
  accept_request boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'You must be signed in.'; end if;
  if not exists (
    select 1 from public.community_friendships
    where id = friendship_id
      and addressee_id = auth.uid()
      and status = 'pending'
  ) then
    raise exception 'This pending request is not available.';
  end if;
  if accept_request then
    update public.community_friendships
    set status = 'accepted', updated_at = now()
    where id = friendship_id;
  else
    delete from public.community_friendships where id = friendship_id;
  end if;
end;
$$;

create or replace function public.remove_community_friendship(friendship_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'You must be signed in.'; end if;
  delete from public.community_friendships
  where id = friendship_id
    and (requester_id = auth.uid() or addressee_id = auth.uid());
end;
$$;

create or replace function public.are_community_friends(first_user uuid, second_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.community_friendships
    where status = 'accepted'
      and least(requester_id, addressee_id) = least(first_user, second_user)
      and greatest(requester_id, addressee_id) = greatest(first_user, second_user)
  );
$$;

-- Replace the room creation functions so only accepted friends can be added.
create or replace function public.create_direct_chat(other_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  conversation_key text;
  result_room_id uuid;
begin
  if caller_id is null then raise exception 'You must be signed in.'; end if;
  if not public.are_community_friends(caller_id, other_user_id) then
    raise exception 'You can only start a private chat with an accepted friend.';
  end if;
  conversation_key := least(caller_id::text, other_user_id::text)
    || ':' || greatest(caller_id::text, other_user_id::text);
  select id into result_room_id from public.community_rooms
  where direct_key = conversation_key;
  if result_room_id is null then
    begin
      insert into public.community_rooms(name, room_type, created_by, direct_key)
      values ('Private chat', 'direct', caller_id, conversation_key)
      returning id into result_room_id;
    exception when unique_violation then
      select id into result_room_id from public.community_rooms
      where direct_key = conversation_key;
    end;
  end if;
  insert into public.community_room_members(room_id, user_id)
  values (result_room_id, caller_id), (result_room_id, other_user_id)
  on conflict do nothing;
  return result_room_id;
end;
$$;

create or replace function public.create_group_chat(group_name text, member_ids uuid[])
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  result_room_id uuid;
  requested_count integer;
  friend_count integer;
begin
  if caller_id is null then raise exception 'You must be signed in.'; end if;
  if char_length(trim(group_name)) not between 1 and 60 then
    raise exception 'Group name must contain 1 to 60 characters.';
  end if;
  select count(distinct member_id) into requested_count
  from unnest(member_ids) as selected(member_id)
  where selected.member_id <> caller_id;
  if requested_count < 1 then raise exception 'Choose at least one friend.'; end if;
  select count(*) into friend_count
  from (
    select distinct value as member_id
    from unnest(member_ids) as item(value)
  ) selected
  where selected.member_id <> caller_id
    and public.are_community_friends(caller_id, selected.member_id);
  if friend_count <> requested_count then
    raise exception 'Every group member must be an accepted friend.';
  end if;
  insert into public.community_rooms(name, room_type, created_by)
  values (trim(group_name), 'group', caller_id)
  returning id into result_room_id;
  insert into public.community_room_members(room_id, user_id)
  values (result_room_id, caller_id);
  insert into public.community_room_members(room_id, user_id)
  select result_room_id, member_id
  from (
    select distinct value as member_id
    from unnest(member_ids) as item(value)
  ) selected
  where member_id <> caller_id;
  return result_room_id;
end;
$$;

revoke all on function public.set_community_username(text) from public;
revoke all on function public.search_community_profiles(text) from public;
revoke all on function public.send_community_friend_request(uuid) from public;
revoke all on function public.respond_community_friend_request(uuid, boolean) from public;
revoke all on function public.remove_community_friendship(uuid) from public;
revoke all on function public.are_community_friends(uuid, uuid) from public;
grant execute on function public.set_community_username(text) to authenticated;
grant execute on function public.search_community_profiles(text) to authenticated;
grant execute on function public.send_community_friend_request(uuid) to authenticated;
grant execute on function public.respond_community_friend_request(uuid, boolean) to authenticated;
grant execute on function public.remove_community_friendship(uuid) to authenticated;
grant execute on function public.are_community_friends(uuid, uuid) to authenticated;
grant execute on function public.create_direct_chat(uuid) to authenticated;
grant execute on function public.create_group_chat(text, uuid[]) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'community_friendships'
  ) then
    alter publication supabase_realtime add table public.community_friendships;
  end if;
end;
$$;
