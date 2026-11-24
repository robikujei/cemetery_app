-- A lot purchase is settled by one approved payment, not installments.
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
  if p_approve then
    select * into ownership from public.lot_ownership where ownership_id=request.ownership_id for update;
    if not found then raise exception 'Ownership record not found'; end if;
    insert into public.transaction_history(ownership_id,amount,payment_date,notes,payment_request_id)
    values(request.ownership_id,request.amount,request.payment_date,p_admin_notes,request.request_id);
    update public.lot_ownership set status='Completed', months_paid=coalesce(total_months,1)
      where ownership_id=request.ownership_id;
  elsif nullif(trim(p_admin_notes),'') is null then
    raise exception 'Provide a reason for rejecting the payment';
  end if;
  update public.payment_requests set status=case when p_approve then 'Approved' else 'Rejected' end,
    admin_notes=p_admin_notes,updated_at=now() where request_id=p_request_id;
end $$;
notify pgrst,'reload schema';
