-- Run this once before using the expanded burial/interment form.
-- It keeps deceased records in burial_record, and stores informants once
-- so the same informant can be linked to multiple burials.

create table if not exists public.burial_informants (
  informant_id bigserial primary key,
  full_name text not null,
  relationship_to_deceased text,
  address text,
  work text,
  cellphone_no text,
  id_presented text,
  id_number text,
  place_issued text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists burial_informants_full_name_idx
  on public.burial_informants (lower(full_name));

create index if not exists burial_informants_cellphone_idx
  on public.burial_informants (cellphone_no);

create or replace function public.set_burial_informants_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_burial_informants_updated_at
  on public.burial_informants;

create trigger set_burial_informants_updated_at
before update on public.burial_informants
for each row
execute function public.set_burial_informants_updated_at();

alter table public.burial_record
  add column if not exists application_date date,
  add column if not exists informant_id bigint
    references public.burial_informants(informant_id) on delete set null,
  add column if not exists religion text,
  add column if not exists interment_date date,
  add column if not exists interment_time time,
  add column if not exists burial_category text,
  add column if not exists bldg_no text,
  add column if not exists niche_no text,
  add column if not exists level text,
  add column if not exists lot_location_no text,
  add column if not exists registered_lot_owner text,
  add column if not exists registered_owner_contact_no text,
  add column if not exists interment_or_number text,
  add column if not exists interment_total numeric(12, 2),
  add column if not exists interment_payment_date date,
  add column if not exists death_certificate_submitted boolean not null default false,
  add column if not exists ownership_certificate_submitted boolean not null default false,
  add column if not exists authority_document_submitted boolean not null default false;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'burial_record'
      and column_name = 'lot_id'
  ) then
    alter table public.burial_record alter column lot_id drop not null;
  end if;
end $$;

update public.burial_record
set interment_date = burial_date
where interment_date is null
  and burial_date is not null;

create index if not exists burial_record_informant_id_idx
  on public.burial_record (informant_id);

create index if not exists burial_record_lot_id_idx
  on public.burial_record (lot_id);
