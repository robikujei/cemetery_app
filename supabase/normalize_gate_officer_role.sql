-- Run once in the Supabase SQL Editor.
-- Converts the legacy Guard role to the role used by the unified app,
-- router, and visitor-check-in policies.

update public.users
set role = 'gate_officer'
where lower(trim(coalesce(role, ''))) in ('guard', 'gate officer', 'gate-officer');

