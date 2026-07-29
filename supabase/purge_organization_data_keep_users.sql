-- Permanently remove all organization/application data while preserving users.
--
-- Preserved:
--   public.users
--   auth.users (not in the public schema and never targeted)
--   public.spatial_ref_sys (PostGIS reference data, when present)
--
-- Run this as one script in the Supabase SQL Editor. The TRUNCATE intentionally
-- does not use CASCADE: if an unexpected table outside this purge references a
-- target table, PostgreSQL will abort and roll back instead of risking users.

begin;

create temporary table purge_user_guard (
  user_count bigint not null
) on commit drop;

insert into purge_user_guard (user_count)
select count(*) from public.users;

do $$
declare
  target_tables text;
begin
  select string_agg(
    format('%I.%I', schemaname, tablename),
    ', ' order by tablename
  )
  into target_tables
  from pg_catalog.pg_tables
  where schemaname = 'public'
    and tablename not in (
      'users',
      'spatial_ref_sys'
    );

  if target_tables is not null then
    execute 'truncate table ' || target_tables || ' restart identity';
  end if;
end
$$;

do $$
declare
  users_before bigint;
  users_after bigint;
begin
  select user_count into users_before from purge_user_guard;
  select count(*) into users_after from public.users;

  if users_after <> users_before then
    raise exception
      'Safety check failed: public.users count changed from % to %',
      users_before,
      users_after;
  end if;
end
$$;

commit;

-- Verification output: users should remain and every other application table
-- should report zero rows.
select 'public.users' as preserved_table, count(*) as remaining_rows
from public.users;

select
  schemaname || '.' || relname as table_name,
  n_live_tup as estimated_remaining_rows
from pg_catalog.pg_stat_user_tables
where schemaname = 'public'
  and relname not in ('users', 'spatial_ref_sys')
order by relname;
