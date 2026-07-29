-- Enables live admin-dashboard updates for Objectives 1-3.
-- Safe to run more than once in the Supabase SQL editor.
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'burial_record',
    'cemetery_lot',
    'lot_ownership',
    'visitor_log'
  ]
  loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = table_name
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        table_name
      );
    end if;
  end loop;
end
$$;
