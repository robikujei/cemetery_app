-- An informant is a reusable contact.  Their relationship is specific to a
-- deceased person, so it belongs on this link rather than on the informant.
create table if not exists public.burial_informant_relationships (
  burial_id bigint primary key references public.burial_record(burial_id)
    on delete cascade,
  informant_id bigint not null references public.burial_informants(informant_id)
    on delete restrict,
  relationship_to_deceased text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists burial_informant_relationships_informant_id_idx
  on public.burial_informant_relationships (informant_id);

create or replace function public.set_burial_informant_relationships_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_burial_informant_relationships_updated_at
  on public.burial_informant_relationships;

create trigger set_burial_informant_relationships_updated_at
before update on public.burial_informant_relationships
for each row execute function public.set_burial_informant_relationships_updated_at();

-- Preserve the old relationship values while moving them to the per-burial
-- link. The legacy column remains for backwards compatibility.
insert into public.burial_informant_relationships (
  burial_id,
  informant_id,
  relationship_to_deceased
)
select
  record.burial_id,
  record.informant_id,
  informant.relationship_to_deceased
from public.burial_record record
join public.burial_informants informant
  on informant.informant_id = record.informant_id
where record.informant_id is not null
on conflict (burial_id) do nothing;
