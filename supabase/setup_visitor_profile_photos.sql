-- Run once in the Supabase SQL Editor before enabling visitor profile photos.
-- Photos are public so they can be shown in the profile UI, but every signed-in
-- user can write or remove files only inside their own Auth UUID folder.

begin;

alter table public.users
  add column if not exists avatar_url text;

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) values (
  'avatars', 'avatars', true, 5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Avatar owner uploads" on storage.objects;
create policy "Avatar owner uploads"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Avatar owner replaces" on storage.objects;
create policy "Avatar owner replaces"
on storage.objects for update to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Avatar owner removes" on storage.objects;
create policy "Avatar owner removes"
on storage.objects for delete to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Keep the profile update limited to the authenticated account. The existing
-- protect_profile_role trigger, when installed, also prevents role changes.
alter table public.users enable row level security;
drop policy if exists "Users update own profile" on public.users;
create policy "Users update own profile"
on public.users for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

select pg_notify('pgrst', 'reload schema');

commit;
