create table if not exists public.apple_iap_notification_receipts (
  notification_uuid uuid primary key,
  notification_type text not null check (btrim(notification_type) <> ''),
  subtype text,
  environment text not null check (environment in ('Sandbox', 'Production')),
  apple_iap_transaction_id uuid
    references public.apple_iap_transactions(id) on delete restrict,
  processed_at timestamptz not null default now()
);

alter table public.apple_iap_notification_receipts enable row level security;

create or replace function public.grant_apple_iap_threads(
  p_user_id uuid,
  p_transaction_id text,
  p_original_transaction_id text,
  p_product_id text,
  p_app_account_token uuid,
  p_purchased_at timestamptz,
  p_environment text,
  p_thread_amount integer
)
returns table(available_threads integer, status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_balance integer;
  iap_transaction_id uuid;
  existing_transaction public.apple_iap_transactions%rowtype;
  expected_thread_amount integer;
begin
  if p_transaction_id is null or btrim(p_transaction_id) = '' then
    raise exception using errcode = '22023', message = 'apple_transaction_id_required';
  end if;
  if p_original_transaction_id is null or btrim(p_original_transaction_id) = '' then
    raise exception using errcode = '22023', message = 'apple_original_transaction_id_required';
  end if;
  if p_purchased_at is null then
    raise exception using errcode = '22023', message = 'apple_purchase_date_required';
  end if;

  expected_thread_amount := case p_product_id
    when 'com.inseong.coordit.thread.5' then 5
    when 'com.inseong.coordit.thread.10' then 10
    when 'com.inseong.coordit.thread.20' then 20
    else null
  end;
  if expected_thread_amount is null or p_thread_amount is distinct from expected_thread_amount then
    raise exception using errcode = '22023', message = 'apple_product_amount_invalid';
  end if;
  if p_environment not in ('Sandbox', 'Production') then
    raise exception using errcode = '22023', message = 'apple_environment_invalid';
  end if;
  if p_app_account_token is distinct from p_user_id then
    raise exception using errcode = '42501', message = 'apple_transaction_account_mismatch';
  end if;

  insert into public.thread_balances(user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  select balance.available_threads
  into current_balance
  from public.thread_balances balance
  where balance.user_id = p_user_id
  for update;

  select transaction.*
  into existing_transaction
  from public.apple_iap_transactions transaction
  where transaction.transaction_id = p_transaction_id
  for update;

  if found then
    if existing_transaction.user_id is distinct from p_user_id
      or existing_transaction.original_transaction_id is distinct from p_original_transaction_id
      or existing_transaction.product_id is distinct from p_product_id
      or existing_transaction.app_account_token is distinct from p_app_account_token
      or existing_transaction.purchased_at is distinct from p_purchased_at
      or existing_transaction.environment is distinct from p_environment then
      raise exception using errcode = '23505', message = 'apple_transaction_metadata_conflict';
    end if;
    return query select current_balance, 'already_credited'::text;
    return;
  end if;

  begin
    insert into public.apple_iap_transactions(
      transaction_id,
      original_transaction_id,
      user_id,
      product_id,
      app_account_token,
      purchased_at,
      environment
    ) values (
      p_transaction_id,
      p_original_transaction_id,
      p_user_id,
      p_product_id,
      p_app_account_token,
      p_purchased_at,
      p_environment
    )
    returning id into iap_transaction_id;
  exception
    when unique_violation then
      select transaction.*
      into existing_transaction
      from public.apple_iap_transactions transaction
      where transaction.transaction_id = p_transaction_id
      for update;

      if not found
        or existing_transaction.user_id is distinct from p_user_id
        or existing_transaction.original_transaction_id is distinct from p_original_transaction_id
        or existing_transaction.product_id is distinct from p_product_id
        or existing_transaction.app_account_token is distinct from p_app_account_token
        or existing_transaction.purchased_at is distinct from p_purchased_at
        or existing_transaction.environment is distinct from p_environment then
        raise exception using errcode = '23505', message = 'apple_transaction_metadata_conflict';
      end if;
      return query select current_balance, 'already_credited'::text;
      return;
  end;

  update public.thread_balances balance
  set available_threads = balance.available_threads + expected_thread_amount,
      updated_at = now()
  where balance.user_id = p_user_id
  returning balance.available_threads into current_balance;

  insert into public.thread_ledger_entries(
    user_id,
    idempotency_key,
    amount,
    reason,
    apple_iap_transaction_id
  ) values (
    p_user_id,
    iap_transaction_id,
    expected_thread_amount,
    'iap_purchase',
    iap_transaction_id
  );

  return query select current_balance, 'credited'::text;
end;
$$;

create or replace function public.record_apple_iap_notification(
  p_notification_uuid uuid,
  p_notification_type text,
  p_subtype text,
  p_environment text
)
returns table(status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted_count integer;
  existing_receipt public.apple_iap_notification_receipts%rowtype;
begin
  if p_notification_type is null or btrim(p_notification_type) = '' then
    raise exception using errcode = '22023', message = 'apple_notification_type_required';
  end if;
  if p_notification_type = 'ONE_TIME_CHARGE' then
    raise exception using errcode = '22023', message = 'apple_notification_reconciliation_required';
  end if;
  if p_environment not in ('Sandbox', 'Production') then
    raise exception using errcode = '22023', message = 'apple_notification_environment_invalid';
  end if;

  insert into public.apple_iap_notification_receipts(
    notification_uuid,
    notification_type,
    subtype,
    environment
  ) values (
    p_notification_uuid,
    p_notification_type,
    p_subtype,
    p_environment
  )
  on conflict (notification_uuid) do nothing;
  get diagnostics inserted_count = row_count;

  if inserted_count = 1 then
    return query select 'processed'::text;
    return;
  end if;

  select receipt.*
  into existing_receipt
  from public.apple_iap_notification_receipts receipt
  where receipt.notification_uuid = p_notification_uuid
  for update;

  if existing_receipt.notification_type is distinct from p_notification_type
    or existing_receipt.subtype is distinct from p_subtype
    or existing_receipt.environment is distinct from p_environment
    or existing_receipt.apple_iap_transaction_id is not null then
    raise exception using errcode = '23505', message = 'apple_notification_metadata_conflict';
  end if;

  return query select 'already_processed'::text;
end;
$$;

create or replace function public.reconcile_apple_iap_notification(
  p_notification_uuid uuid,
  p_notification_type text,
  p_subtype text,
  p_environment text,
  p_user_id uuid,
  p_transaction_id text,
  p_original_transaction_id text,
  p_product_id text,
  p_app_account_token uuid,
  p_purchased_at timestamptz,
  p_transaction_environment text,
  p_thread_amount integer
)
returns table(available_threads integer, status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  credit_result record;
  iap_transaction_id uuid;
  inserted_count integer;
  existing_receipt public.apple_iap_notification_receipts%rowtype;
begin
  if p_notification_type is distinct from 'ONE_TIME_CHARGE' then
    raise exception using errcode = '22023', message = 'apple_notification_type_invalid';
  end if;
  if p_environment is distinct from p_transaction_environment then
    raise exception using errcode = '22023', message = 'apple_notification_environment_mismatch';
  end if;

  select grant_result.available_threads, grant_result.status
  into credit_result
  from public.grant_apple_iap_threads(
    p_user_id,
    p_transaction_id,
    p_original_transaction_id,
    p_product_id,
    p_app_account_token,
    p_purchased_at,
    p_transaction_environment,
    p_thread_amount
  ) grant_result;

  select transaction.id
  into iap_transaction_id
  from public.apple_iap_transactions transaction
  where transaction.transaction_id = p_transaction_id;

  insert into public.apple_iap_notification_receipts(
    notification_uuid,
    notification_type,
    subtype,
    environment,
    apple_iap_transaction_id
  ) values (
    p_notification_uuid,
    p_notification_type,
    p_subtype,
    p_environment,
    iap_transaction_id
  )
  on conflict (notification_uuid) do nothing;
  get diagnostics inserted_count = row_count;

  if inserted_count = 1 then
    return query select credit_result.available_threads, credit_result.status::text;
    return;
  end if;

  select receipt.*
  into existing_receipt
  from public.apple_iap_notification_receipts receipt
  where receipt.notification_uuid = p_notification_uuid
  for update;

  if existing_receipt.notification_type is distinct from p_notification_type
    or existing_receipt.subtype is distinct from p_subtype
    or existing_receipt.environment is distinct from p_environment
    or existing_receipt.apple_iap_transaction_id is distinct from iap_transaction_id then
    raise exception using errcode = '23505', message = 'apple_notification_metadata_conflict';
  end if;

  return query select credit_result.available_threads, 'already_processed'::text;
end;
$$;

revoke all on table public.apple_iap_notification_receipts from anon, authenticated;
revoke all on function public.grant_apple_iap_threads(
  uuid, text, text, text, uuid, timestamptz, text, integer
) from public, anon, authenticated;
revoke all on function public.record_apple_iap_notification(
  uuid, text, text, text
) from public, anon, authenticated;
revoke all on function public.reconcile_apple_iap_notification(
  uuid, text, text, text, uuid, text, text, text, uuid, timestamptz, text, integer
) from public, anon, authenticated;

grant execute on function public.grant_apple_iap_threads(
  uuid, text, text, text, uuid, timestamptz, text, integer
) to service_role;
grant execute on function public.record_apple_iap_notification(
  uuid, text, text, text
) to service_role;
grant execute on function public.reconcile_apple_iap_notification(
  uuid, text, text, text, uuid, text, text, text, uuid, timestamptz, text, integer
) to service_role;
