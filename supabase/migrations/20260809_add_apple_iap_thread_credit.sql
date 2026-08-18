create table if not exists public.apple_iap_transactions (
  id uuid primary key default gen_random_uuid(),
  transaction_id text not null unique,
  original_transaction_id text not null,
  user_id uuid not null references public.users(id) on delete cascade,
  product_id text not null,
  app_account_token uuid not null,
  purchased_at timestamptz not null,
  environment text not null check (environment in ('Sandbox', 'Production')),
  created_at timestamptz not null default now(),
  check (app_account_token = user_id)
);

alter table public.thread_ledger_entries
  add column if not exists apple_iap_transaction_id uuid
  references public.apple_iap_transactions(id) on delete cascade;

create unique index if not exists idx_thread_ledger_entries_apple_iap_transaction
  on public.thread_ledger_entries(apple_iap_transaction_id)
  where apple_iap_transaction_id is not null;

alter table public.apple_iap_transactions enable row level security;

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
language plpgsql security definer set search_path = public
as $$
declare
  current_balance integer;
  iap_transaction_id uuid;
  existing_user_id uuid;
begin
  if p_thread_amount <= 0 then
    raise exception 'Thread amount must be positive';
  end if;
  if p_environment not in ('Sandbox', 'Production') then
    raise exception 'Unsupported Apple environment';
  end if;
  if p_app_account_token is distinct from p_user_id then
    raise exception 'Apple transaction belongs to another user';
  end if;

  insert into public.thread_balances(user_id) values (p_user_id)
  on conflict (user_id) do nothing;

  select balance.available_threads into current_balance
  from public.thread_balances balance
  where balance.user_id = p_user_id
  for update;

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
  on conflict (transaction_id) do nothing
  returning id into iap_transaction_id;

  if iap_transaction_id is null then
    select transaction.user_id into existing_user_id
    from public.apple_iap_transactions transaction
    where transaction.transaction_id = p_transaction_id;

    if existing_user_id is distinct from p_user_id then
      raise exception 'Apple transaction belongs to another user';
    end if;

    return query select current_balance, 'already_credited'::text;
    return;
  end if;

  update public.thread_balances
  set available_threads = thread_balances.available_threads + p_thread_amount,
      updated_at = now()
  where user_id = p_user_id
  returning thread_balances.available_threads into current_balance;

  insert into public.thread_ledger_entries(
    user_id,
    idempotency_key,
    amount,
    reason,
    apple_iap_transaction_id
  ) values (
    p_user_id,
    iap_transaction_id,
    p_thread_amount,
    'iap_purchase',
    iap_transaction_id
  );

  return query select current_balance, 'credited'::text;
end;
$$;

revoke all on table public.apple_iap_transactions from anon, authenticated;
revoke all on function public.grant_apple_iap_threads(uuid, text, text, text, uuid, timestamptz, text, integer)
  from public, anon, authenticated;
grant execute on function public.grant_apple_iap_threads(uuid, text, text, text, uuid, timestamptz, text, integer)
  to service_role;
