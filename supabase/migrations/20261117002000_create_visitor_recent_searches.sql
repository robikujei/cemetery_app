create table if not exists public.visitor_recent_searches (
  recent_search_id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  burial_id integer not null references public.burial_record(burial_id) on delete cascade,
  lot_id integer references public.cemetery_lot(lot_id) on delete set null,
  deceased_name text not null,
  details text,
  lot_number text,
  search_type text not null default 'deceased',
  searched_at timestamptz not null default now(),
  unique (user_id, burial_id)
);

alter table public.visitor_recent_searches enable row level security;

create policy "Visitors can read their recent searches"
on public.visitor_recent_searches for select
to authenticated
using (auth.uid() = user_id);

create policy "Visitors can add their recent searches"
on public.visitor_recent_searches for insert
to authenticated
with check (auth.uid() = user_id);

create policy "Visitors can update their recent searches"
on public.visitor_recent_searches for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "Visitors can delete their recent searches"
on public.visitor_recent_searches for delete
to authenticated
using (auth.uid() = user_id);

grant select, insert, update, delete on public.visitor_recent_searches to authenticated;
grant usage, select on sequence public.visitor_recent_searches_recent_search_id_seq to authenticated;
