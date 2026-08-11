create table public.admob_reward_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','granted','expired')),
  expires_at timestamptz not null default now() + interval '15 minutes',
  granted_at timestamptz,
  created_at timestamptz not null default now()
);
create table public.admob_reward_transactions (
  transaction_id text primary key,
  attempt_id uuid not null unique references public.admob_reward_attempts(id),
  created_at timestamptz not null default now()
);
alter table public.admob_reward_attempts enable row level security;
alter table public.admob_reward_transactions enable row level security;
revoke all on public.admob_reward_attempts, public.admob_reward_transactions from anon, authenticated;
alter table public.thread_ledger_entries drop constraint if exists thread_ledger_entries_reason_check;
alter table public.thread_ledger_entries add constraint thread_ledger_entries_reason_check check (reason in ('fit_analysis','iap_purchase','ad_reward','admin_adjustment'));

create or replace function public.create_admob_reward_attempt(p_user_id uuid)
returns table(id uuid, status text, expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  return query insert into public.admob_reward_attempts(user_id) values (p_user_id)
  returning admob_reward_attempts.id, admob_reward_attempts.status, admob_reward_attempts.expires_at;
end; $$;

create or replace function public.grant_admob_reward(p_attempt_id uuid, p_transaction_id text)
returns table(available_threads integer, status text)
language plpgsql security definer set search_path = public as $$
declare attempt public.admob_reward_attempts; balance integer;
begin
  select * into attempt from public.admob_reward_attempts where id = p_attempt_id for update;
  if not found then return query select 0, 'unknown_attempt'::text; return; end if;
  insert into public.thread_balances(user_id) values (attempt.user_id) on conflict (user_id) do nothing;
  select available_threads into balance from public.thread_balances where user_id = attempt.user_id for update;
  if exists (select 1 from public.admob_reward_transactions where transaction_id = p_transaction_id) or attempt.status = 'granted' then
    return query select balance, 'already_granted'::text; return;
  end if;
  if attempt.expires_at < now() then
    update public.admob_reward_attempts set status = 'expired' where id = attempt.id;
    return query select balance, 'expired'::text; return;
  end if;
  update public.thread_balances set available_threads = available_threads + 1, updated_at = now()
  where user_id = attempt.user_id returning available_threads into balance;
  insert into public.thread_ledger_entries(user_id,idempotency_key,fit_analysis_result_id,amount,reason)
  values (attempt.user_id,attempt.id,null,1,'ad_reward');
  insert into public.admob_reward_transactions(transaction_id,attempt_id) values (p_transaction_id,attempt.id);
  update public.admob_reward_attempts set status = 'granted', granted_at = now() where id = attempt.id;
  return query select balance, 'granted'::text;
end; $$;
revoke all on function public.create_admob_reward_attempt(uuid) from public, anon, authenticated;
revoke all on function public.grant_admob_reward(uuid,text) from public, anon, authenticated;
grant execute on function public.create_admob_reward_attempt(uuid) to service_role;
grant execute on function public.grant_admob_reward(uuid,text) to service_role;
