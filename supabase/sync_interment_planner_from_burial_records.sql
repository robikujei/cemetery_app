-- Run once in the Supabase SQL Editor.
--
-- A burial record is the source of truth for an interment recorded through
-- any form. When it has a lot, interment date, and interment time, this
-- trigger keeps its matching planner item in sync automatically.
-- Manual planner items remain supported: they simply have burial_id = NULL.

begin;

alter table public.interment_schedule
  add column if not exists burial_id bigint
  references public.burial_record(burial_id) on delete cascade;

create unique index if not exists interment_schedule_burial_id_unique
  on public.interment_schedule(burial_id)
  where burial_id is not null;

create or replace function public.sync_interment_schedule_from_burial()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    delete from public.interment_schedule where burial_id = old.burial_id;
    return old;
  end if;

  -- A record without complete scheduling information is not an active plan.
  if new.lot_id is null
     or new.interment_date is null
     or nullif(trim(coalesce(new.interment_time::text, '')), '') is null then
    delete from public.interment_schedule where burial_id = new.burial_id;
    return new;
  end if;

  insert into public.interment_schedule (
    burial_id, lot_id, deceased_name, scheduled_at, notes, status
  ) values (
    new.burial_id,
    new.lot_id,
    coalesce(nullif(trim(new.name_of_deceased), ''), 'Unnamed interment'),
    -- Form date/time inputs are entered in the cemetery's local timezone.
    (new.interment_date::date + new.interment_time::time) at time zone 'Asia/Manila',
    null,
    'scheduled'
  )
  on conflict (burial_id) where burial_id is not null do update set
    lot_id = excluded.lot_id,
    deceased_name = excluded.deceased_name,
    scheduled_at = excluded.scheduled_at,
    status = case
      when public.interment_schedule.status = 'completed' then 'completed'
      else 'scheduled'
    end,
    updated_at = now();

  return new;
end;
$$;

drop trigger if exists sync_interment_schedule_from_burial on public.burial_record;
create trigger sync_interment_schedule_from_burial
after insert or update or delete on public.burial_record
for each row execute function public.sync_interment_schedule_from_burial();

-- Backfill every existing complete interment record immediately.
insert into public.interment_schedule (
  burial_id, lot_id, deceased_name, scheduled_at, notes, status
)
select
  b.burial_id,
  b.lot_id,
  coalesce(nullif(trim(b.name_of_deceased), ''), 'Unnamed interment'),
  (b.interment_date::date + b.interment_time::time) at time zone 'Asia/Manila',
  null,
  'scheduled'
from public.burial_record b
where b.lot_id is not null
  and b.interment_date is not null
  and nullif(trim(coalesce(b.interment_time::text, '')), '') is not null
on conflict (burial_id) where burial_id is not null do update set
  lot_id = excluded.lot_id,
  deceased_name = excluded.deceased_name,
  scheduled_at = excluded.scheduled_at,
  updated_at = now();

select pg_notify('pgrst', 'reload schema');

commit;

-- Expected after running: zero rows. Any returned burial needs its date/time
-- checked because it could not be synchronized into the planner.
select burial_id, name_of_deceased, lot_id, interment_date, interment_time
from public.burial_record
where lot_id is not null
  and interment_date is not null
  and nullif(trim(coalesce(interment_time::text, '')), '') is not null
  and not exists (
    select 1 from public.interment_schedule schedule
    where schedule.burial_id = burial_record.burial_id
  );
