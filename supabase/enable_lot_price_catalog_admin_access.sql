-- Run after set_fixed_lot_prices_and_interment_fee.sql.
-- Only administrators may inspect or change the editable price schedule.
alter table public.lot_price_catalog enable row level security;

drop policy if exists lot_price_catalog_admin_access on public.lot_price_catalog;
create policy lot_price_catalog_admin_access
on public.lot_price_catalog
for all to authenticated
using (public.paper_user_role() = 'admin')
with check (public.paper_user_role() = 'admin');
