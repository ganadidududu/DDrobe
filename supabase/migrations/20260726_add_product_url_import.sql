alter table public.external_products
  add column if not exists source_url text,
  add column if not exists source_site text,
  add column if not exists source_product_id text,
  add column if not exists thumbnail_url text,
  add column if not exists raw_category text,
  add column if not exists normalized_category text,
  add column if not exists imported_from_url boolean not null default false,
  add column if not exists import_metadata jsonb not null default '{}'::jsonb;

create table if not exists public.product_import_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete set null,
  source_url text not null,
  source_site text,
  product_id text,
  status text not null,
  error_code text,
  warnings jsonb not null default '[]'::jsonb,
  extraction_methods jsonb not null default '[]'::jsonb,
  duration_ms integer,
  created_at timestamptz not null default now()
);

create index if not exists idx_external_products_source_url
  on public.external_products(source_url);
create index if not exists idx_product_import_logs_user_created
  on public.product_import_logs(user_id, created_at desc);

alter table public.product_import_logs enable row level security;

drop policy if exists "product import logs owner read" on public.product_import_logs;
create policy "product import logs owner read"
  on public.product_import_logs for select
  using (auth.uid() = user_id);
