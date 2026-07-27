alter table public.users enable row level security;
alter table public.consent_versions enable row level security;
alter table public.user_consents enable row level security;
alter table public.body_measurements enable row level security;
alter table public.clothing_items enable row level security;
alter table public.clothing_sizes enable row level security;
alter table public.reference_clothing enable row level security;
alter table public.external_products enable row level security;
alter table public.product_import_logs enable row level security;
alter table public.external_product_sizes enable row level security;
alter table public.fit_analysis_results enable row level security;
alter table public.clothing_fit_assessments enable row level security;
alter table public.user_feedback enable row level security;
alter table public.recommendation_logs enable row level security;

create policy "users can read own profile" on public.users for select using (auth.uid() = id);
create policy "users can update own profile" on public.users for update using (auth.uid() = id);

create policy "authenticated users can read consent versions" on public.consent_versions for select using (auth.role() = 'authenticated');

create policy "users can read own consents" on public.user_consents for select using (auth.uid() = user_id);
create policy "users can insert own consents" on public.user_consents for insert with check (auth.uid() = user_id);
create policy "users can update own consents" on public.user_consents for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "body measurements owner access" on public.body_measurements for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "clothing items owner access" on public.clothing_items for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "clothing sizes owner access" on public.clothing_sizes for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "reference clothing owner access" on public.reference_clothing for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "external products owner access" on public.external_products for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "product import logs owner read" on public.product_import_logs for select using (auth.uid() = user_id);
create policy "external product sizes owner access" on public.external_product_sizes for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "fit results owner access" on public.fit_analysis_results for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "clothing fit assessments owner read" on public.clothing_fit_assessments for select using (auth.uid() = user_id);

revoke all on table public.clothing_fit_assessments from anon, authenticated;
grant select on table public.clothing_fit_assessments to authenticated;
create policy "feedback owner access" on public.user_feedback for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "recommendation logs owner access" on public.recommendation_logs for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
