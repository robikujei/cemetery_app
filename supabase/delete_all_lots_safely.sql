-- Run this in Supabase SQL Editor if you want to clear all lot data now.
-- It deletes known child rows before deleting cemetery_lot rows, so it does
-- not depend on ON DELETE CASCADE already being configured.

begin;

delete from public.visitor_log
where burial_id in (
  select burial_id from public.burial_record
);

do $$
begin
  if to_regclass('public.graves') is not null then
    delete from public.graves;
  end if;
end $$;

delete from public.burial_record;

delete from public.payment_requests
where ownership_id in (
  select ownership_id from public.lot_ownership
);

delete from public.transaction_history
where ownership_id in (
  select ownership_id from public.lot_ownership
);

delete from public.lot_ownership;
delete from public.lot_markers;
delete from public.cemetery_lot;

commit;
