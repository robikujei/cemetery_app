-- Run once in Supabase SQL Editor as the project/database administrator.
-- Repairs the Gate Officer sign-in flow for every account created with the
-- Gate Officer role in Supabase Auth metadata.

begin;

-- Legacy accounts can have the correct email and role in public.users but an
-- old user_id from a previous Auth account. Relink those profiles first.
update public.users as profile
set
  user_id = auth_account.id,
  role = 'gate_officer',
  password = coalesce(profile.password, 'managed_by_auth')
from auth.users as auth_account
where lower(profile.email) = lower(auth_account.email)
  and (
    lower(trim(coalesce(profile.role, '')))
      in ('guard', 'gate_officer', 'gate officer', 'gate-officer')
    or lower(trim(coalesce(auth_account.raw_user_meta_data ->> 'role', '')))
      in ('guard', 'gate_officer', 'gate officer', 'gate-officer')
  )
  and profile.user_id is distinct from auth_account.id;

-- The Flutter app must be able to read the signed-in user's own profile.
-- Without this, RLS makes a real profile look "missing" to Gate Officers.
drop policy if exists "Users read own profile" on public.users;
create policy "Users read own profile"
on public.users
for select
to authenticated
using (user_id = auth.uid());

-- Normalize the old role name used by earlier versions of the app.
update public.users
set role = 'gate_officer'
where lower(trim(coalesce(role, ''))) in ('guard', 'gate officer', 'gate-officer');

-- Recreate a missing public profile for every Auth account explicitly marked
-- as a Gate Officer when it was created. Their existing Auth password is not
-- changed. Accounts without Gate Officer metadata are intentionally untouched.
with gate_accounts as (
  select
    id,
    lower(email) as email,
    coalesce(
      nullif(trim(raw_user_meta_data ->> 'name'), ''),
      split_part(email, '@', 1)
    ) as name,
    nullif(trim(raw_user_meta_data ->> 'phone'), '') as phone
  from auth.users
  where lower(trim(coalesce(raw_user_meta_data ->> 'role', '')))
    in ('gate_officer', 'guard', 'gate officer', 'gate-officer')
)
insert into public.users (user_id, name, email, phone, role, password)
select id, name, email, phone, 'gate_officer', 'managed_by_auth'
from gate_accounts
on conflict (user_id) do update
set
  role = 'gate_officer',
  name = excluded.name,
  email = excluded.email,
  phone = coalesce(public.users.phone, excluded.phone),
  password = coalesce(public.users.password, 'managed_by_auth');

commit;

-- Verification: every Gate Officer profile should show profile_user_id equal
-- to auth_user_id. Any false value needs its exact email repaired manually.
select
  auth_account.email,
  auth_account.id as auth_user_id,
  profile.user_id as profile_user_id,
  profile.role,
  profile.user_id = auth_account.id as linked_correctly
from auth.users as auth_account
left join public.users as profile
  on lower(profile.email) = lower(auth_account.email)
where lower(trim(coalesce(profile.role, '')))
  in ('gate_officer', 'guard', 'gate officer', 'gate-officer')
  or lower(trim(coalesce(auth_account.raw_user_meta_data ->> 'role', '')))
    in ('gate_officer', 'guard', 'gate officer', 'gate-officer')
order by auth_account.email;
