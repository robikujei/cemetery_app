begin;
create or replace function public.audit_record_change() returns trigger
language plpgsql security definer set search_path=public as $$
declare row_data jsonb; actor_role text;
begin
  row_data := case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
  select role into actor_role from public.users where user_id=auth.uid();
  insert into public.audit_log(user_id,user_role,action,entity_type,entity_id,details)
    values(auth.uid(),coalesce(actor_role,'system'),tg_op,tg_table_name,
      row_data->>tg_argv[0],'Database record '||lower(tg_op));
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
do $$
declare item record;
begin
  for item in select * from (values
    ('cemetery_lot','lot_id'), ('burial_record','burial_id'),
    ('lot_ownership','ownership_id'), ('transaction_history','transaction_id'),
    ('cemetery_map','map_id'), ('cemetery_map_features','feature_id'),
    ('lot_markers','marker_id'), ('path_nodes','node_id'), ('path_edges','edge_id'),
    ('graves','grave_id')
  ) as targets(table_name,id_column) loop
    execute format('drop trigger if exists paper_record_audit on public.%I',item.table_name);
    execute format('create trigger paper_record_audit after insert or update or delete on public.%I '
      'for each row execute function public.audit_record_change(%L)',item.table_name,item.id_column);
  end loop;
end $$;
commit;
