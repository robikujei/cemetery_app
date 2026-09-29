-- Additive workflows. Apply once using the Supabase SQL editor or CLI.
begin;

create or replace function public.paper_user_role() returns text
language sql stable security definer set search_path = public
as $$ select role::text from public.users where user_id = auth.uid() $$;
revoke all on function public.paper_user_role() from public;
grant execute on function public.paper_user_role() to authenticated;

-- Prevent client-side privilege escalation through the profile table.
create or replace function public.protect_profile_role() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user in ('anon','authenticated') then
    if auth.uid() is null then raise exception 'Authentication required'; end if;
    if tg_op = 'INSERT' then
      if new.user_id <> auth.uid() or new.role <> 'visitor' then
        raise exception 'Use the administrator account service to create roles';
      end if;
    elsif (new.role is distinct from old.role or new.user_id is distinct from old.user_id) then
      raise exception 'Use the administrator account service to change roles';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists paper_protect_role on public.users;
create trigger paper_protect_role before insert or update on public.users
for each row execute function public.protect_profile_role();

alter table public.visitor_log add column if not exists time_out timestamptz;
alter table public.transaction_history add column if not exists payment_request_id integer
  references public.payment_requests(request_id) on delete set null;
create unique index if not exists transaction_payment_request_unique
  on public.transaction_history(payment_request_id) where payment_request_id is not null;

create or replace function public.protect_financial_writes() returns trigger
language plpgsql set search_path=public as $$
begin
  if current_user in ('anon','authenticated') and
    public.paper_user_role() is distinct from 'admin' then
    raise exception 'Use the payment request workflow; administrator access required';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
drop trigger if exists paper_financial_writes on public.lot_ownership;
create trigger paper_financial_writes before insert or update or delete on public.lot_ownership
for each row execute function public.protect_financial_writes();
drop trigger if exists paper_financial_writes on public.transaction_history;
create trigger paper_financial_writes before insert or update or delete on public.transaction_history
for each row execute function public.protect_financial_writes();

alter table public.lot_ownership enable row level security;
drop policy if exists paper_ownership_read on public.lot_ownership;
create policy paper_ownership_read on public.lot_ownership for select to authenticated
using (user_id=auth.uid() or public.paper_user_role() in ('admin','gate_officer'));
drop policy if exists paper_ownership_admin on public.lot_ownership;
create policy paper_ownership_admin on public.lot_ownership for all to authenticated
using (public.paper_user_role()='admin') with check (public.paper_user_role()='admin');
alter table public.transaction_history enable row level security;
drop policy if exists paper_transaction_read on public.transaction_history;
create policy paper_transaction_read on public.transaction_history for select to authenticated
using (public.paper_user_role()='admin' or exists (select 1 from public.lot_ownership o
  where o.ownership_id=transaction_history.ownership_id and o.user_id=auth.uid()));
drop policy if exists paper_transaction_admin on public.transaction_history;
create policy paper_transaction_admin on public.transaction_history for all to authenticated
using (public.paper_user_role()='admin') with check (public.paper_user_role()='admin');
alter table public.visitor_log enable row level security;
drop policy if exists paper_visit_read on public.visitor_log;
create policy paper_visit_read on public.visitor_log for select to authenticated
using (user_id=auth.uid() or public.paper_user_role() in ('admin','gate_officer'));
drop policy if exists paper_visit_staff on public.visitor_log;
create policy paper_visit_staff on public.visitor_log for all to authenticated
using (public.paper_user_role() in ('admin','gate_officer'))
with check (public.paper_user_role() in ('admin','gate_officer'));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('payment-proofs','payment-proofs',false,5242880,array['image/jpeg','image/png'])
on conflict (id) do nothing;
drop policy if exists paper_proof_upload on storage.objects;
create policy paper_proof_upload on storage.objects for insert to authenticated
with check (bucket_id='payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists paper_proof_read on storage.objects;
create policy paper_proof_read on storage.objects for select to authenticated
using (bucket_id='payment-proofs' and ((storage.foldername(name))[1]=auth.uid()::text
  or public.paper_user_role()='admin'));

alter table public.payment_requests enable row level security;
drop policy if exists paper_request_read on public.payment_requests;
create policy paper_request_read on public.payment_requests for select to authenticated
using (public.paper_user_role()='admin' or exists (
  select 1 from public.lot_ownership o where o.ownership_id=payment_requests.ownership_id and o.user_id=auth.uid()
));
revoke all on public.payment_requests from anon;
revoke insert,update,delete on public.payment_requests from authenticated;
grant select on public.payment_requests to authenticated;
grant delete on public.payment_requests to authenticated;
drop policy if exists paper_request_admin_delete on public.payment_requests;
create policy paper_request_admin_delete on public.payment_requests for delete to authenticated
using (public.paper_user_role()='admin');

create or replace function public.submit_payment_request(
  p_ownership_id integer, p_amount numeric, p_payment_date date,
  p_receipt_path text, p_notes text default null
) returns integer language plpgsql security definer set search_path=public as $$
declare result_id integer;
begin
  if auth.uid() is null or not exists (select 1 from public.lot_ownership
    where ownership_id=p_ownership_id and user_id=auth.uid()) then
    raise exception 'You can submit payments only for your own lot';
  end if;
  if p_amount is null or p_amount<=0 or p_amount::text in ('NaN','Infinity','-Infinity') or
    p_payment_date is null or p_payment_date>(now() at time zone 'Asia/Manila')::date then
    raise exception 'Enter a positive amount and a valid payment date';
  end if;
  if p_receipt_path is null or split_part(p_receipt_path,'/',1)<>auth.uid()::text or
    not exists (select 1 from storage.objects where bucket_id='payment-proofs' and name=p_receipt_path) then
    raise exception 'Upload proof of payment first';
  end if;
  insert into public.payment_requests(ownership_id,amount,payment_date,receipt_url,notes,status,created_at,updated_at)
  values(p_ownership_id,p_amount,p_payment_date,p_receipt_path,p_notes,'Pending',now(),now()) returning request_id into result_id;
  insert into public.audit_log(user_id,user_role,action,entity_type,entity_id,details)
  values(auth.uid(),public.paper_user_role(),'SUBMIT_PAYMENT','payment_requests',result_id::text,'Payment submitted for review');
  return result_id;
end $$;

create or replace function public.review_payment_request(
  p_request_id integer, p_approve boolean, p_admin_notes text default null,
  p_months_credit integer default 0
) returns void language plpgsql security definer set search_path=public as $$
declare request public.payment_requests%rowtype; ownership public.lot_ownership%rowtype;
begin
  if public.paper_user_role() is distinct from 'admin' then raise exception 'Administrator access required'; end if;
  select * into request from public.payment_requests where request_id=p_request_id for update;
  if not found then raise exception 'Payment request not found'; end if;
  if lower(coalesce(request.status,''))<>'pending' then raise exception 'This request has already been reviewed'; end if;
  if request.amount is null or request.amount<=0 or request.amount::text in ('NaN','Infinity','-Infinity') then
    raise exception 'Invalid payment amount';
  end if;
  if p_approve is null then raise exception 'Choose approve or reject'; end if;
  select * into ownership from public.lot_ownership where ownership_id=request.ownership_id for update;
  if not found then raise exception 'Ownership record not found'; end if;
  if p_months_credit is null or p_months_credit<0 or
    p_months_credit>greatest(ownership.total_months-coalesce(ownership.months_paid,0),0) then
    raise exception 'Month credit exceeds the remaining installments';
  end if;
  if p_approve then
    insert into public.transaction_history(ownership_id,amount,payment_date,notes,payment_request_id)
    values(request.ownership_id,request.amount,request.payment_date,p_admin_notes,request.request_id);
    if p_months_credit>0 then
      update public.lot_ownership set months_paid=coalesce(months_paid,0)+p_months_credit,
        status=case when coalesce(months_paid,0)+p_months_credit>=total_months then 'Completed' else status end
      where ownership_id=request.ownership_id;
    end if;
  elsif nullif(trim(p_admin_notes),'') is null then
    raise exception 'Provide a reason for rejecting the payment';
  end if;
  update public.payment_requests set status=case when p_approve then 'Approved' else 'Rejected' end,
    admin_notes=p_admin_notes,updated_at=now() where request_id=p_request_id;
  insert into public.audit_log(user_id,user_role,action,entity_type,entity_id,details)
  values(auth.uid(),'admin',case when p_approve then 'APPROVE_PAYMENT' else 'REJECT_PAYMENT' end,
    'payment_requests',p_request_id::text,p_admin_notes);
end $$;

create or replace function public.record_gate_visit(p_visitor_id uuid,
  p_burial_id integer default null, p_direction text default 'entry')
returns jsonb language plpgsql security definer set search_path=public as $$
declare open_id integer; result_id integer;
begin
  if public.paper_user_role() is null or public.paper_user_role() not in ('admin','gate_officer') then
    raise exception 'Gate officer access required';
  end if;
  if p_direction is null or p_direction not in ('entry','exit') then raise exception 'Invalid scan direction'; end if;
  if not exists(select 1 from public.users where user_id=p_visitor_id) then raise exception 'Visitor not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_visitor_id::text,0));
  select log_id into open_id from public.visitor_log where user_id=p_visitor_id and time_out is null
    order by time_in desc limit 1 for update;
  if p_direction='exit' then
    if open_id is null then raise exception 'No open entry for this visitor'; end if;
    update public.visitor_log set time_out=now() where log_id=open_id;
    result_id:=open_id;
  else
    if open_id is not null then return jsonb_build_object('alreadyCheckedIn',true,'logId',open_id); end if;
    insert into public.visitor_log(user_id,burial_id,time_in,method)
    values(p_visitor_id,p_burial_id,now() at time zone 'Asia/Manila','QR') returning log_id into result_id;
  end if;
  insert into public.audit_log(user_id,user_role,action,entity_type,entity_id,details)
  values(auth.uid(),public.paper_user_role(),case when p_direction='entry' then 'VISITOR_ENTRY' else 'VISITOR_EXIT' end,
    'visitor_log',result_id::text,'QR visitor '||p_direction);
  return jsonb_build_object('success',true,'logId',result_id,'direction',p_direction);
end $$;

revoke all on function public.submit_payment_request(integer,numeric,date,text,text) from public;
revoke all on function public.review_payment_request(integer,boolean,text,integer) from public;
revoke all on function public.record_gate_visit(uuid,integer,text) from public;
grant execute on function public.submit_payment_request(integer,numeric,date,text,text) to authenticated;
grant execute on function public.review_payment_request(integer,boolean,text,integer) to authenticated;
grant execute on function public.record_gate_visit(uuid,integer,text) to authenticated;
notify pgrst,'reload schema';
commit;
