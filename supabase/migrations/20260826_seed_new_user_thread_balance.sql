begin;

do $$
begin
  if to_regclass('public.users') is null or to_regclass('public.thread_balances') is null then
    raise exception using errcode = '55000', message = 'new_user_wallet_prerequisite_missing';
  end if;

  if not exists (
    select 1
    from pg_attribute attribute
    where attribute.attrelid = 'public.thread_balances'::regclass
      and attribute.attname = 'available_threads'
      and not attribute.attisdropped
      and attribute.atttypid = 'integer'::regtype
      and attribute.attnotnull
  ) then
    raise exception using errcode = '55000', message = 'new_user_wallet_catalog_drift';
  end if;
end
$$;

alter table public.thread_balances
  alter column available_threads set default 3;

create or replace function public.seed_new_user_thread_balance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.thread_balances(user_id, available_threads)
  values (new.id, 3)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists seed_new_user_thread_balance on public.users;
create trigger seed_new_user_thread_balance
after insert on public.users
for each row execute function public.seed_new_user_thread_balance();

revoke all on function public.seed_new_user_thread_balance() from public, anon, authenticated;

commit;
