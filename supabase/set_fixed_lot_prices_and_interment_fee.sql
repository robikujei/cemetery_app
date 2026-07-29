-- Fixed cemetery price catalog. cemetery_lot.price remains as the legacy
-- at-need price column so existing app queries and reports stay compatible.

create table if not exists public.lot_price_catalog (
  lot_type text primary key,
  at_need_price numeric(12, 2) not null check (at_need_price >= 0),
  pre_need_price numeric(12, 2) not null check (pre_need_price >= 0),
  updated_at timestamptz not null default now()
);

insert into public.lot_price_catalog (
  lot_type,
  at_need_price,
  pre_need_price
)
values
  ('Super Prime A', 40518, 25527),
  ('Super Prime B', 34729, 21880),
  ('Super Prime C', 28942, 18234),
  ('Prime A', 34729, 21880),
  ('Prime B', 28942, 18234),
  ('Regular Lot', 23153, 14587),
  ('Corner Lot', 52094, 32819),
  ('Family Estate', 694575, 437583)
on conflict (lot_type) do update
set
  at_need_price = excluded.at_need_price,
  pre_need_price = excluded.pre_need_price,
  updated_at = now();

alter table public.cemetery_lot
  add column if not exists pricing_type text;

update public.cemetery_lot lot
set pricing_type = case
  when lot.price = catalog.at_need_price then 'at_need'
  else 'pre_need'
end
from public.lot_price_catalog catalog
where lower(trim(lot.lot_class_type)) = lower(catalog.lot_type)
  and (
    lot.pricing_type is null
    or lot.pricing_type not in ('at_need', 'pre_need')
  );

update public.cemetery_lot
set pricing_type = 'pre_need'
where pricing_type is null
   or pricing_type not in ('at_need', 'pre_need');

alter table public.cemetery_lot
  alter column pricing_type set default 'pre_need',
  alter column pricing_type set not null;

alter table public.cemetery_lot
  drop constraint if exists cemetery_lot_pricing_type_check;

alter table public.cemetery_lot
  add constraint cemetery_lot_pricing_type_check
  check (pricing_type in ('at_need', 'pre_need'));

drop trigger if exists cemetery_lot_fixed_price on public.cemetery_lot;

-- Normalize the lot type imported from QGIS and apply its fixed at-need price.
update public.cemetery_lot
set lot_class_type = 'Regular Lot'
where lower(trim(coalesce(lot_class_type, ''))) in ('', 'regular lot');

update public.cemetery_lot lot
set price = case
  when lot.pricing_type = 'at_need' then catalog.at_need_price
  else catalog.pre_need_price
end
from public.lot_price_catalog catalog
where lower(trim(lot.lot_class_type)) = lower(catalog.lot_type);

create or replace function public.apply_fixed_lot_price()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  fixed_price numeric(12, 2);
  fixed_pre_need_price numeric(12, 2);
  canonical_type text;
begin
  select lot_type, at_need_price, pre_need_price
  into canonical_type, fixed_price, fixed_pre_need_price
  from public.lot_price_catalog
  where lower(lot_type) = lower(trim(new.lot_class_type))
  limit 1;

  if fixed_price is null then
    raise exception 'Unknown lot type: %', new.lot_class_type;
  end if;

  new.lot_class_type := canonical_type;
  if new.pricing_type is null
     or new.pricing_type not in ('at_need', 'pre_need') then
    new.pricing_type := 'pre_need';
  end if;
  new.price := case
    when new.pricing_type = 'at_need' then fixed_price
    else fixed_pre_need_price
  end;
  return new;
end;
$$;

create trigger cemetery_lot_fixed_price
before insert or update of lot_class_type, pricing_type, price
on public.cemetery_lot
for each row execute function public.apply_fixed_lot_price();

alter table public.burial_record
  alter column interment_total set default 13313;
