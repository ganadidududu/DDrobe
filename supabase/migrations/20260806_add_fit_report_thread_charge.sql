alter table public.thread_ledger_entries
  drop constraint if exists thread_ledger_entries_reason_check;

alter table public.thread_ledger_entries
  add constraint thread_ledger_entries_reason_check
  check (reason in ('fit_analysis', 'fit_report', 'iap_purchase', 'admin_adjustment'));

alter table public.thread_ledger_entries
  drop constraint if exists thread_ledger_entries_user_id_idempotency_key_key;

alter table public.thread_ledger_entries
  add constraint thread_ledger_entries_user_id_idempotency_key_reason_key
  unique (user_id, idempotency_key, reason);

create or replace function public.consume_fit_report_thread(
  p_user_id uuid,
  p_idempotency_key uuid,
  p_fit_analysis_result_id uuid
)
returns table(available_threads integer, status text)
language plpgsql security definer set search_path = public
as $$
declare current_balance integer;
begin
  insert into public.thread_balances(user_id) values (p_user_id)
  on conflict (user_id) do nothing;

  select balance.available_threads into current_balance
  from public.thread_balances balance
  where balance.user_id = p_user_id
  for update;

  if exists (
    select 1 from public.thread_ledger_entries entry
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

  update public.thread_balances
  set available_threads = thread_balances.available_threads - 1, updated_at = now()
  where user_id = p_user_id
  returning thread_balances.available_threads into current_balance;

  insert into public.thread_ledger_entries(
    user_id, idempotency_key, fit_analysis_result_id, amount, reason
  ) values (p_user_id, p_idempotency_key, p_fit_analysis_result_id, -1, 'fit_report');

  return query select current_balance, 'consumed'::text;
end;
$$;

revoke all on function public.consume_fit_report_thread(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.consume_fit_report_thread(uuid, uuid, uuid) to service_role;

create or replace function public.consume_fit_analysis_thread(
  p_user_id uuid, p_idempotency_key uuid, p_fit_analysis_result_id uuid
)
returns table(available_threads integer, status text)
language plpgsql security definer set search_path = public
as $$
declare current_balance integer;
begin
  insert into public.thread_balances(user_id) values (p_user_id)
  on conflict (user_id) do nothing;

  select balance.available_threads into current_balance
  from public.thread_balances balance
  where balance.user_id = p_user_id
  for update;

  if exists (
    select 1 from public.thread_ledger_entries entry
    where entry.user_id = p_user_id
      and entry.idempotency_key = p_idempotency_key
      and entry.reason = 'fit_analysis'
  ) then
    return query select current_balance, 'already_consumed'::text;
    return;
  end if;

  if current_balance <= 0 then
    return query select current_balance, 'insufficient'::text;
    return;
  end if;

  update public.thread_balances
  set available_threads = thread_balances.available_threads - 1, updated_at = now()
  where user_id = p_user_id
  returning available_threads into current_balance;

  insert into public.thread_ledger_entries(
    user_id, idempotency_key, fit_analysis_result_id, amount, reason
  ) values (p_user_id, p_idempotency_key, p_fit_analysis_result_id, -1, 'fit_analysis');

  return query select current_balance, 'consumed'::text;
end;
$$;

create or replace function public.create_fit_analysis_result_and_consume_thread(
  p_user_id uuid,
  p_idempotency_key uuid,
  p_result jsonb
)
returns table(fit_analysis_result_id uuid, available_threads integer, status text)
language plpgsql security definer set search_path = public
as $$
declare
  current_balance integer;
  saved_result public.fit_analysis_results;
  existing_result_id uuid;
begin
  insert into public.thread_balances(user_id) values (p_user_id)
  on conflict (user_id) do nothing;

  select balance.available_threads into current_balance
  from public.thread_balances balance
  where balance.user_id = p_user_id
  for update;

  select entry.fit_analysis_result_id into existing_result_id
  from public.thread_ledger_entries entry
  where entry.user_id = p_user_id
    and entry.idempotency_key = p_idempotency_key
    and entry.reason = 'fit_analysis';
  if found then
    return query select existing_result_id, current_balance, 'already_consumed'::text;
    return;
  end if;

  if current_balance <= 0 then
    return query select null::uuid, current_balance, 'insufficient'::text;
    return;
  end if;

  insert into public.fit_analysis_results (
    user_id,
    reference_clothing_id,
    external_product_id,
    recommended_external_product_size_id,
    recommended_size_label,
    fit_score,
    fit_label,
    fit_comment,
    weighted_fit_distance,
    algorithm_version,
    recommendation_confidence,
    result_details
  ) values (
    p_user_id,
    (p_result->>'referenceClothingId')::uuid,
    (p_result->>'externalProductId')::uuid,
    (p_result->>'recommendedExternalProductSizeId')::uuid,
    p_result->>'recommendedSizeLabel',
    (p_result->>'fitScore')::numeric,
    p_result->>'fitLabel',
    p_result->>'fitComment',
    (p_result->>'weightedFitDistance')::numeric,
    p_result->>'algorithmVersion',
    p_result->>'recommendationConfidence',
    coalesce(p_result->'resultDetails', '{}'::jsonb)
  ) returning * into saved_result;

  update public.thread_balances
  set available_threads = thread_balances.available_threads - 1, updated_at = now()
  where user_id = p_user_id
  returning thread_balances.available_threads into current_balance;

  insert into public.thread_ledger_entries(
    user_id, idempotency_key, fit_analysis_result_id, amount, reason
  ) values (p_user_id, p_idempotency_key, saved_result.id, -1, 'fit_analysis');

  insert into public.recommendation_logs(
    user_id, fit_analysis_result_id, external_product_id, recommended_size_label,
    event_type, algorithm_version, raw_data
  ) values (
    p_user_id,
    saved_result.id,
    saved_result.external_product_id,
    saved_result.recommended_size_label,
    'shown',
    saved_result.algorithm_version,
    jsonb_build_object('source', 'fit_recommend_api')
  );

  return query select saved_result.id, current_balance, 'consumed'::text;
end;
$$;
