-- Integration checks use existing role identities, temporary fixtures, and ROLLBACK.
begin;
do $$
declare
  admin_id uuid; owner_id uuid; visitor_id uuid; req_id integer; visit_id integer;
  proof_path text; denied boolean; response jsonb;
begin
  select user_id into admin_id from public.users where role='admin' limit 1;
  select user_id into owner_id from public.users where role='lot_owner' limit 1;
  select user_id into visitor_id from public.users where role='visitor' limit 1;
  if admin_id is null or owner_id is null or visitor_id is null then
    raise exception 'Test requires an existing admin, lot owner, and visitor';
  end if;
  insert into public.cemetery_lot(lot_id,lot_number,lot_class_type,status,price,x_coord,y_coord)
    values(-987654321,'WORKFLOW-ROLLBACK-TEST','Regular Lot','Available',1000,125,7);
  insert into public.lot_ownership(ownership_id,lot_id,total_months,months_paid,start_date,status,user_id)
    values(-987654321,-987654321,12,0,current_date,'Active',owner_id);
  proof_path := owner_id::text||'/workflow-rollback-test.png';
  insert into storage.objects(bucket_id,name) values('payment-proofs',proof_path);
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  execute 'set local role authenticated';
  req_id := public.submit_payment_request(-987654321,100,current_date,proof_path,'Rollback test');
  denied:=false;
  begin
    perform public.review_payment_request(req_id,true,'Invalid owner approval',1);
  exception when raise_exception then denied:=true;
  end;
  if not denied then raise exception 'Owner approval was not denied'; end if;
  denied:=false;
  begin
    update public.lot_ownership set months_paid=12 where ownership_id=-987654321;
  exception when raise_exception then denied:=true;
  end;
  if (select months_paid from public.lot_ownership where ownership_id=-987654321)<>0 then
    raise exception 'Owner could forge installment credits';
  end if;
  perform set_config('request.jwt.claim.sub',visitor_id::text,true);
  if exists(select 1 from public.payment_requests where request_id=req_id) then
    raise exception 'Another visitor can read the private payment request';
  end if;
  denied:=false;
  begin
    perform public.submit_payment_request(-987654321,100,current_date,proof_path,'Not owner');
  exception when raise_exception then denied:=true;
  end;
  if not denied then raise exception 'Non-owner payment submission was accepted'; end if;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  perform public.review_payment_request(req_id,true,'Verified rollback test',1);
  denied:=false;
  begin
    perform public.review_payment_request(req_id,true,'Duplicate',1);
  exception when raise_exception then denied:=true;
  end;
  if not denied then raise exception 'Duplicate approval accepted'; end if;
  if (select count(*) from public.transaction_history where payment_request_id=req_id)<>1 then
    raise exception 'Approval did not create exactly one transaction';
  end if;
  if (select months_paid from public.lot_ownership where ownership_id=-987654321)<>1 then
    raise exception 'Installment credits incorrect';
  end if;
  -- Use the owner identity as visitor to avoid modifying an actual open visitor visit.
  response:=public.record_gate_visit(owner_id,null,'entry');
  visit_id:=(response->>'logId')::integer;
  response:=public.record_gate_visit(owner_id,null,'entry');
  if response->>'alreadyCheckedIn'<>'true' then raise exception 'Duplicate gate entry was accepted'; end if;
  perform public.record_gate_visit(owner_id,null,'exit');
  if (select time_out from public.visitor_log where log_id=visit_id) is null then
    raise exception 'Checkout did not record exit time';
  end if;
  perform set_config('request.jwt.claim.sub',visitor_id::text,true);
  denied:=false;
  begin
    perform public.record_gate_visit(owner_id,null,'entry');
  exception when raise_exception then denied:=true;
  end;
  if not denied then raise exception 'Visitor could operate gate workflow'; end if;
  execute 'reset role';
end $$;
rollback;
