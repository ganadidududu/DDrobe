alter table public.users
  add column if not exists is_guest boolean not null default false;

alter table public.thread_balances
  alter column available_threads set default 0;

alter table public.thread_ledger_entries
  drop constraint if exists thread_ledger_entries_reason_check;

alter table public.thread_ledger_entries
  add constraint thread_ledger_entries_reason_check
  check (reason in (
    'welcome_grant',
    'fit_analysis',
    'fit_report',
    'iap_purchase',
    'ad_reward',
    'admin_adjustment'
  ));

create table if not exists public.guest_welcome_claims (
  user_id uuid primary key references public.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'eligible', 'granted', 'denied')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.guest_welcome_claims enable row level security;

create or replace function public.prepare_guest_welcome_claim(p_user_id uuid)
returns table(status text)
language plpgsql security definer set search_path = public
as $$
begin
  if not exists (
    select 1 from public.users where id = p_user_id and is_guest = true
  ) then
    raise exception 'Guest user was not found' using errcode = 'P0002';
  end if;

  insert into public.guest_welcome_claims(user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  return query
  select claim.status
  from public.guest_welcome_claims claim
  where claim.user_id = p_user_id
  for update;
end;
$$;

create or replace function public.mark_guest_welcome_eligible(p_user_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update public.guest_welcome_claims
  set status = 'eligible', updated_at = now()
  where user_id = p_user_id and status = 'pending';

  if not found then
    raise exception 'Guest welcome claim is not pending' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function public.complete_guest_welcome_claim(p_user_id uuid)
returns table(available_threads integer)
language plpgsql security definer set search_path = public
as $$
declare
  claim_status text;
  current_balance integer;
  welcome_idempotency_key uuid;
begin
  select claim.status into claim_status
  from public.guest_welcome_claims claim
  where claim.user_id = p_user_id
  for update;

  if claim_status is null then
    raise exception 'Guest welcome claim was not prepared' using errcode = 'P0002';
  end if;

  insert into public.thread_balances(user_id, available_threads)
  values (p_user_id, 0)
  on conflict (user_id) do nothing;

  if claim_status = 'eligible' then
    select id into welcome_idempotency_key
    from auth.users
    where id = p_user_id;

    update public.thread_balances
    set available_threads = thread_balances.available_threads + 3,
        updated_at = now()
    where user_id = p_user_id;

    insert into public.thread_ledger_entries(
      user_id, idempotency_key, amount, reason
    ) values (
      p_user_id, welcome_idempotency_key, 3, 'welcome_grant'
    ) on conflict (user_id, idempotency_key) do nothing;

    update public.guest_welcome_claims
    set status = 'granted', updated_at = now()
    where user_id = p_user_id;
  elsif claim_status <> 'granted' then
    raise exception 'Guest welcome claim is not eligible' using errcode = 'P0001';
  end if;

  select balance.available_threads into current_balance
  from public.thread_balances balance
  where balance.user_id = p_user_id;

  return query select current_balance;
end;
$$;

create or replace function public.deny_guest_welcome_claim(p_user_id uuid)
returns table(available_threads integer)
language plpgsql security definer set search_path = public
as $$
begin
  update public.guest_welcome_claims
  set status = 'denied', updated_at = now()
  where user_id = p_user_id and status in ('pending', 'denied');

  insert into public.thread_balances(user_id, available_threads)
  values (p_user_id, 0)
  on conflict (user_id) do nothing;

  return query
  select balance.available_threads
  from public.thread_balances balance
  where balance.user_id = p_user_id;
end;
$$;

create or replace function public.merge_guest_account(
  p_guest_user_id uuid,
  p_member_user_id uuid
)
returns table(available_threads integer)
language plpgsql security definer set search_path = public
as $$
declare
  merged_balance integer;
begin
  if p_guest_user_id = p_member_user_id then
    raise exception 'Guest and member users must differ' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.users where id = p_guest_user_id and is_guest = true
  ) then
    raise exception 'Guest user was not found' using errcode = 'P0002';
  end if;
  if not exists (
    select 1 from public.users where id = p_member_user_id and is_guest = false
  ) then
    raise exception 'Member user was not found' using errcode = 'P0002';
  end if;

  insert into public.thread_balances(user_id, available_threads)
  values (p_member_user_id, 0)
  on conflict (user_id) do nothing;

  perform 1 from public.thread_balances
  where user_id in (p_guest_user_id, p_member_user_id)
  order by user_id
  for update;

  delete from public.user_consents guest_consent
  using public.user_consents member_consent
  where guest_consent.user_id = p_guest_user_id
    and member_consent.user_id = p_member_user_id
    and guest_consent.consent_key = member_consent.consent_key
    and guest_consent.consent_version = member_consent.consent_version;
  update public.user_consents set user_id = p_member_user_id where user_id = p_guest_user_id;
  update public.body_measurements set user_id = p_member_user_id where user_id = p_guest_user_id;
  update public.clothing_items set user_id = p_member_user_id where user_id = p_guest_user_id;
  update public.clothing_sizes set user_id = p_member_user_id where user_id = p_guest_user_id;
  update public.reference_clothing set user_id = p_member_user_id where user_id = p_guest_user_id;
  update public.external_products set user_id = p_member_user_id where user_id = p_guest_user_id;
  update public.product_import_logs set user_id = p_member_user_id where user_id = p_guest_user_id;
  update public.external_product_sizes set user_id = p_member_user_id where user_id = p_guest_user_id;
  update public.fit_analysis_results set user_id = p_member_user_id where user_id = p_guest_user_id;
  update public.clothing_fit_assessments set user_id = p_member_user_id where user_id = p_guest_user_id;
  update public.user_feedback set user_id = p_member_user_id where user_id = p_guest_user_id;
  update public.recommendation_logs set user_id = p_member_user_id where user_id = p_guest_user_id;
  update public.styling_looks set user_id = p_member_user_id where user_id = p_guest_user_id;

  delete from public.clothing_item_save_requests guest_request
  using public.clothing_item_save_requests member_request
  where guest_request.user_id = p_guest_user_id
    and member_request.user_id = p_member_user_id
    and guest_request.idempotency_key = member_request.idempotency_key;
  update public.clothing_item_save_requests
  set user_id = p_member_user_id
  where user_id = p_guest_user_id;

  delete from public.thread_ledger_entries guest_entry
  using public.thread_ledger_entries member_entry
  where guest_entry.user_id = p_guest_user_id
    and member_entry.user_id = p_member_user_id
    and guest_entry.idempotency_key = member_entry.idempotency_key;
  update public.thread_ledger_entries
  set user_id = p_member_user_id
  where user_id = p_guest_user_id;

  update public.thread_balances member_balance
  set available_threads = member_balance.available_threads + coalesce(
        (select guest_balance.available_threads
         from public.thread_balances guest_balance
         where guest_balance.user_id = p_guest_user_id),
        0
      ),
      updated_at = now()
  where member_balance.user_id = p_member_user_id
  returning member_balance.available_threads into merged_balance;

  delete from public.thread_balances where user_id = p_guest_user_id;
  delete from public.guest_welcome_claims where user_id = p_guest_user_id;
  delete from public.users where id = p_guest_user_id;

  return query select merged_balance;
end;
$$;

revoke all on table public.guest_welcome_claims from public, anon, authenticated;
revoke all on function public.prepare_guest_welcome_claim(uuid) from public, anon, authenticated;
revoke all on function public.mark_guest_welcome_eligible(uuid) from public, anon, authenticated;
revoke all on function public.complete_guest_welcome_claim(uuid) from public, anon, authenticated;
revoke all on function public.deny_guest_welcome_claim(uuid) from public, anon, authenticated;
revoke all on function public.merge_guest_account(uuid, uuid) from public, anon, authenticated;
grant execute on function public.prepare_guest_welcome_claim(uuid) to service_role;
grant execute on function public.mark_guest_welcome_eligible(uuid) to service_role;
grant execute on function public.complete_guest_welcome_claim(uuid) to service_role;
grant execute on function public.deny_guest_welcome_claim(uuid) to service_role;
grant execute on function public.merge_guest_account(uuid, uuid) to service_role;
