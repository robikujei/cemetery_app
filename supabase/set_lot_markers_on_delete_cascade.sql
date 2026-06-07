-- Run this in Supabase SQL Editor.
-- Allows deleting a cemetery_lot row directly while automatically removing
-- matching lot_markers rows.
--
-- The final select should show delete_rule = CASCADE for
-- lot_markers_lot_id_fkey.

select
  tc.constraint_name,
  rc.delete_rule
from information_schema.table_constraints tc
join information_schema.referential_constraints rc
  on rc.constraint_schema = tc.constraint_schema
 and rc.constraint_name = tc.constraint_name
where tc.table_schema = 'public'
  and tc.table_name = 'lot_markers'
  and tc.constraint_type = 'FOREIGN KEY';

begin;

do $$
declare
  fk_name text;
begin
  for fk_name in
    select c.conname
    from pg_constraint c
    join pg_class child on child.oid = c.conrelid
    join pg_namespace child_ns on child_ns.oid = child.relnamespace
    join pg_class parent on parent.oid = c.confrelid
    join pg_namespace parent_ns on parent_ns.oid = parent.relnamespace
    where c.contype = 'f'
      and child_ns.nspname = 'public'
      and child.relname = 'lot_markers'
      and parent_ns.nspname = 'public'
      and parent.relname = 'cemetery_lot'
  loop
    execute format('alter table public.lot_markers drop constraint %I', fk_name);
  end loop;
end $$;

alter table public.lot_markers
add constraint lot_markers_lot_id_fkey
foreign key (lot_id)
references public.cemetery_lot(lot_id)
on update cascade
on delete cascade;

commit;

select
  tc.constraint_name,
  rc.update_rule,
  rc.delete_rule
from information_schema.table_constraints tc
join information_schema.referential_constraints rc
  on rc.constraint_schema = tc.constraint_schema
 and rc.constraint_name = tc.constraint_name
where tc.table_schema = 'public'
  and tc.table_name = 'lot_markers'
  and tc.constraint_type = 'FOREIGN KEY';
