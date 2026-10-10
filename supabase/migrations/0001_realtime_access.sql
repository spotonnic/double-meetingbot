-- Only glanser.com people (signed in with Google) and registered robot accounts
-- may join the private Realtime channel "double-office".

create schema if not exists private;
grant usage on schema private to authenticated;

-- Service accounts for the iPads. Rows are added by an admin (see README); no API access.
create table if not exists private.double_robots (
  user_id uuid primary key references auth.users (id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);
alter table private.double_robots enable row level security;
revoke all on private.double_robots from anon, authenticated;

create or replace function private.is_double_member()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (
      lower(coalesce(auth.jwt() ->> 'email', '')) like '%@glanser.com'
      and coalesce(auth.jwt() -> 'app_metadata' -> 'providers', '[]'::jsonb) ? 'google'
    )
    or exists (select 1 from private.double_robots r where r.user_id = auth.uid());
$$;

revoke all on function private.is_double_member() from public;
grant execute on function private.is_double_member() to authenticated;

-- Realtime Authorization: covers broadcast and presence on private channels.
drop policy if exists "double members can receive" on realtime.messages;
create policy "double members can receive"
  on realtime.messages for select to authenticated
  using (realtime.topic() = 'double-office' and private.is_double_member());

drop policy if exists "double members can send" on realtime.messages;
create policy "double members can send"
  on realtime.messages for insert to authenticated
  with check (realtime.topic() = 'double-office' and private.is_double_member());
