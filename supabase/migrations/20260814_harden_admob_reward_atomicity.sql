alter table public.thread_ledger_entries
  drop constraint if exists thread_ledger_entries_reason_check;

alter table public.thread_ledger_entries
  add constraint thread_ledger_entries_reason_check
  check (reason in ('fit_analysis', 'fit_report', 'iap_purchase', 'ad_reward', 'admin_adjustment'));

create or replace function public.grant_admob_reward(
  p_attempt_id uuid,
  p_transaction_id text
)
returns table(available_threads integer, status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  reward_attempt public.admob_reward_attempts%rowtype;
  current_balance integer;
  existing_attempt_id uuid;
begin
  if p_transaction_id is null or btrim(p_transaction_id) = '' then
    raise exception using
      errcode = '22023',
      message = 'admob_transaction_id_required';
  end if;

  select attempt.*
  into reward_attempt
  from public.admob_reward_attempts attempt
  where attempt.id = p_attempt_id
  for update;

  if not found then
    return query select 0, 'unknown_attempt'::text;
    return;
  end if;

  select reward_transaction.attempt_id
  into existing_attempt_id
  from public.admob_reward_transactions reward_transaction
  where reward_transaction.transaction_id = p_transaction_id
  for update;

  if found then
    if existing_attempt_id is distinct from reward_attempt.id then
      raise exception using
        errcode = '23505',
        message = 'admob_transaction_attempt_conflict';
    end if;

    insert into public.thread_balances(user_id)
    values (reward_attempt.user_id)
    on conflict (user_id) do nothing;

    select balance.available_threads
    into current_balance
    from public.thread_balances balance
    where balance.user_id = reward_attempt.user_id
    for update;

    return query select current_balance, 'already_granted'::text;
    return;
  end if;

  if reward_attempt.status = 'granted' then
    raise exception using
      errcode = '23505',
      message = 'admob_attempt_transaction_conflict';
  end if;

  insert into public.thread_balances(user_id)
  values (reward_attempt.user_id)
  on conflict (user_id) do nothing;

  select balance.available_threads
  into current_balance
  from public.thread_balances balance
  where balance.user_id = reward_attempt.user_id
  for update;

  if reward_attempt.status = 'expired' or reward_attempt.expires_at < now() then
    update public.admob_reward_attempts attempt
    set status = 'expired'
    where attempt.id = reward_attempt.id;

    return query select current_balance, 'expired'::text;
    return;
  end if;

  begin
    insert into public.admob_reward_transactions(transaction_id, attempt_id)
    values (p_transaction_id, reward_attempt.id);
  exception
    when unique_violation then
      select reward_transaction.attempt_id
      into existing_attempt_id
      from public.admob_reward_transactions reward_transaction
      where reward_transaction.transaction_id = p_transaction_id
      for update;

      if found and existing_attempt_id = reward_attempt.id then
        return query select current_balance, 'already_granted'::text;
        return;
      end if;

      raise exception using
        errcode = '23505',
        message = 'admob_transaction_attempt_conflict';
  end;

  update public.thread_balances balance
  set available_threads = balance.available_threads + 1,
      updated_at = now()
  where balance.user_id = reward_attempt.user_id
  returning balance.available_threads into current_balance;

  insert into public.thread_ledger_entries(
    user_id,
    idempotency_key,
    fit_analysis_result_id,
    amount,
    reason
  ) values (
    reward_attempt.user_id,
    reward_attempt.id,
    null,
    1,
    'ad_reward'
  );

  update public.admob_reward_attempts attempt
  set status = 'granted',
      granted_at = now()
  where attempt.id = reward_attempt.id;

  return query select current_balance, 'granted'::text;
end;
$$;

create or replace function public.consume_fit_report_thread(
  p_user_id uuid,
  p_idempotency_key uuid,
  p_fit_analysis_result_id uuid
)
returns table(available_threads integer, status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_balance integer;
begin
  insert into public.thread_balances(user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  select balance.available_threads
  into current_balance
  from public.thread_balances balance
  where balance.user_id = p_user_id
  for update;

  if exists (
    select 1
    from public.thread_ledger_entries entry
    where entry.user_id = p_user_id
      and entry.idempotency_key = p_idempotency_key
      and entry.reason = 'fit_report'
  ) then
    return query select current_balance, 'already_consumed'::text;
    return;
  end if;

  if current_balance <= 0 then
    return query select current_balance, 'insufficient'::text;
    return;
  end if;

  update public.thread_balances balance
  set available_threads = balance.available_threads - 1,
      updated_at = now()
  where balance.user_id = p_user_id
  returning balance.available_threads into current_balance;

  insert into public.thread_ledger_entries(
    user_id,
    idempotency_key,
    fit_analysis_result_id,
    amount,
    reason
  ) values (
    p_user_id,
    p_idempotency_key,
    p_fit_analysis_result_id,
    -1,
    'fit_report'
  );

  return query select current_balance, 'consumed'::text;
end;
$$;

revoke all on function public.grant_admob_reward(uuid, text)
  from public, anon, authenticated;
revoke all on function public.consume_fit_report_thread(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.grant_admob_reward(uuid, text)
  to service_role;
grant execute on function public.consume_fit_report_thread(uuid, uuid, uuid)
  to service_role;
