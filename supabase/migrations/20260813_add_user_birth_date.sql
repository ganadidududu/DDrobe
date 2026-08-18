alter table public.users
  add column if not exists birth_date date;
