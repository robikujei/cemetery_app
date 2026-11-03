-- Weekly planner entries. Run once in Supabase SQL Editor.
create table if not exists public.interment_schedule (
  schedule_id bigserial primary key,
  lot_id integer not null references public.cemetery_lot(lot_id) on delete restrict,
  deceased_name text not null,
  scheduled_at timestamptz not null,
  notes text,
  status text not null default 'scheduled' check (status in ('scheduled','completed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists interment_schedule_week_idx on public.interment_schedule(scheduled_at);
create index if not exists interment_schedule_lot_idx on public.interment_schedule(lot_id);
alter table public.interment_schedule enable row level security;
create policy "Admins manage interment schedules" on public.interment_schedule for all to authenticated
using (exists (select 1 from public.users where user_id=auth.uid() and role='admin'))
with check (exists (select 1 from public.users where user_id=auth.uid() and role='admin'));
create policy "Visitors read active schedules" on public.interment_schedule for select to authenticated
using (status='scheduled');
