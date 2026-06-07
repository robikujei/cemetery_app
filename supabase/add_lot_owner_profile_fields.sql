-- Run this in Supabase SQL Editor before using the expanded lot-owner form.
-- Stores the Panabo City Eternal Garden purchaser profile on public.users.

alter table public.users
  add column if not exists control_number text,
  add column if not exists first_name text,
  add column if not exists middle_name text,
  add column if not exists last_name text,
  add column if not exists address text,
  add column if not exists occupation text,
  add column if not exists age integer,
  add column if not exists civil_status text,
  add column if not exists date_of_birth date,
  add column if not exists gender text,
  add column if not exists spouse_beneficiary text,
  add column if not exists beneficiary_relationship text,
  add column if not exists lot_class_type text,
  add column if not exists block_number text,
  add column if not exists lot_number text,
  add column if not exists number_of_lots integer,
  add column if not exists purchase_term text,
  add column if not exists lot_price numeric(12, 2),
  add column if not exists interment_fee numeric(12, 2),
  add column if not exists certification_fee numeric(12, 2),
  add column if not exists burial_permit_fee numeric(12, 2),
  add column if not exists total_amount numeric(12, 2),
  add column if not exists or_number text,
  add column if not exists receipt_amount numeric(12, 2),
  add column if not exists receipt_date date,
  add column if not exists approved_date date,
  add column if not exists approved_by_name text,
  add column if not exists approval_signature text;

create index if not exists users_role_lot_owner_idx
  on public.users (role)
  where role = 'lot_owner';

create index if not exists users_control_number_idx
  on public.users (control_number)
  where control_number is not null;

-- Ask Supabase/PostgREST to refresh its schema cache so the Flutter app
-- can immediately select the newly added purchaser-profile columns.
select pg_notify('pgrst', 'reload schema');
