-- Run once in Supabase SQL Editor.
-- Replace the email below with the Gate Officer's exact sign-in email.
-- This keeps the existing Supabase Auth password and creates the missing
-- application profile required by the unified app.

with gate_account as (
  select
    id,
    lower(email) as email,
    coalesce(
      nullif(trim(raw_user_meta_data ->> 'name'), ''),
      split_part(email, '@', 1)
    ) as name,
    nullif(trim(raw_user_meta_data ->> 'phone'), '') as phone
  from auth.users
  where lower(email) = lower('REPLACE_WITH_GATE_OFFICER_EMAIL@example.com')
)
insert into public.users (user_id, name, email, phone, role, password)
select id, name, email, phone, 'gate_officer', 'managed_by_auth'
from gate_account
on conflict (user_id) do update
set
  name = excluded.name,
  email = excluded.email,
  phone = excluded.phone,
  role = 'gate_officer',
  password = coalesce(public.users.password, 'managed_by_auth');

-- Expected result: "Success. No rows returned".
-- If it says 0 rows affected, check the email spelling or confirm the
-- account exists under Authentication > Users in Supabase.
