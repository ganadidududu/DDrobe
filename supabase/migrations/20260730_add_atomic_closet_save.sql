create table if not exists public.clothing_item_save_requests (
  user_id uuid not null references public.users(id) on delete cascade,
  idempotency_key uuid not null,
  clothing_item_id uuid references public.clothing_items(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, idempotency_key)
);

alter table public.clothing_item_save_requests enable row level security;

-- Remove the older non-idempotent overload when upgrading an existing database.
drop function if exists public.create_clothing_item_with_size(uuid, jsonb, jsonb);

create or replace function public.create_clothing_item_with_size(
  p_user_id uuid,
  p_item jsonb,
  p_size jsonb,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  saved_item public.clothing_items;
  saved_size public.clothing_sizes;
  existing_item_id uuid;
begin
  insert into public.clothing_item_save_requests(user_id, idempotency_key)
  values (p_user_id, p_idempotency_key)
  on conflict (user_id, idempotency_key) do nothing;

  select request.clothing_item_id into existing_item_id
  from public.clothing_item_save_requests request
  where request.user_id = p_user_id
    and request.idempotency_key = p_idempotency_key
  for update;

  if existing_item_id is not null then
    select * into saved_item
    from public.clothing_items
    where id = existing_item_id and user_id = p_user_id;
    select * into saved_size
    from public.clothing_sizes
    where clothing_item_id = existing_item_id and user_id = p_user_id
    order by created_at asc
    limit 1;
    if saved_item.id is null or saved_size.id is null then
      raise exception 'Saved clothing request is incomplete';
    end if;
    return jsonb_build_object(
      'clothingItem', to_jsonb(saved_item),
      'clothingSize', to_jsonb(saved_size)
    );
  end if;

  insert into public.clothing_items (
    user_id, name, brand, category, fit_type, size_label, notes, image_url, raw_product_data
  ) values (
    p_user_id,
    p_item->>'name',
    p_item->>'brand',
    p_item->>'category',
    coalesce(p_item->>'fit_type', p_item->>'fitType', 'regular'),
    coalesce(p_item->>'size_label', p_item->>'sizeLabel'),
    p_item->>'notes',
    p_item->>'image_url',
    coalesce(p_item->'raw_product_data', p_item->'rawProductData', '{}'::jsonb)
  ) returning * into saved_item;

  insert into public.clothing_sizes (
    user_id, clothing_item_id, size_label, total_length, shoulder_width, chest_width,
    sleeve_length, waist_width, hip_width, rise, outseam, raw_measurements
  ) values (
    p_user_id,
    saved_item.id,
    coalesce(p_size->>'size_label', p_size->>'sizeLabel'),
    nullif(p_size->>'total_length', '')::numeric,
    nullif(p_size->>'shoulder_width', '')::numeric,
    nullif(p_size->>'chest_width', '')::numeric,
    nullif(p_size->>'sleeve_length', '')::numeric,
    nullif(p_size->>'waist_width', '')::numeric,
    nullif(p_size->>'hip_width', '')::numeric,
    nullif(p_size->>'rise', '')::numeric,
    nullif(p_size->>'outseam', '')::numeric,
    coalesce(p_size->'raw_measurements', p_size->'rawMeasurements', '{}'::jsonb)
  ) returning * into saved_size;

  update public.clothing_item_save_requests
  set clothing_item_id = saved_item.id
  where user_id = p_user_id and idempotency_key = p_idempotency_key;

  return jsonb_build_object(
    'clothingItem', to_jsonb(saved_item),
    'clothingSize', to_jsonb(saved_size)
  );
end;
$$;

revoke all on table public.clothing_item_save_requests from anon, authenticated;
revoke all on function public.create_clothing_item_with_size(uuid, jsonb, jsonb, uuid) from public, anon, authenticated;
grant execute on function public.create_clothing_item_with_size(uuid, jsonb, jsonb, uuid) to service_role;
