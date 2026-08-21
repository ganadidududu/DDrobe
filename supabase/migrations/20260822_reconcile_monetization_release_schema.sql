-- allow: SIZE_OK — this single forward migration atomically reconciles the inseparable release monetary schema and RPC contract.

do $$
declare
  runner_filename text := current_setting('coordit.reconciliation_filename', true);
  runner_sha256 text := current_setting('coordit.reconciliation_sha256', true);
  grant_admob_definition text;
  normalized_grant_admob_definition text;
  stale_admob_declaration_fragment text :=
    'declare attempt public.admob_reward_attempts; balance integer;';
  stale_admob_replay_fragment text :=
    'if exists (select 1 from public.admob_reward_transactions where transaction_id = p_transaction_id) or attempt.status = ''granted'' then';
  grant_apple_definition text;
  record_notification_definition text;
  reconcile_notification_definition text;
  core_catalog_valid boolean := false;
  stale_admob_valid boolean := false;
  hardened_admob_valid boolean := false;
  apple_absent boolean := false;
  apple_exact boolean := false;
  markers_absent boolean := false;
  markers_exact boolean := false;
  records_absent boolean := false;
  records_exact boolean := false;
  record_table_exact boolean := false;
  recorded_disposition text;
begin
  if runner_filename is distinct from '20260822_reconcile_monetization_release_schema.sql'
    or runner_sha256 is null
    or runner_sha256 !~ '^[0-9a-f]{64}$'
    or current_setting('coordit.reconciliation_lock_acquired', true) is distinct from 'on'
    or current_setting('lock_timeout') not in ('5s', '5000ms')
    or current_setting('statement_timeout') not in ('30s', '30000ms') then
    raise exception using
      errcode = '55000',
      message = 'monetization_reconciliation_runner_context_required';
  end if;

  if to_regclass('supabase_migrations.schema_migrations') is not null then
    raise exception using
      errcode = '55000',
      message = 'monetization_catalog_drift',
      detail = 'unexpected_supabase_migration_ledger';
  end if;

  if to_regclass('public.users') is null
    or to_regclass('public.fit_analysis_results') is null
    or to_regclass('public.thread_balances') is null
    or to_regclass('public.thread_ledger_entries') is null
    or to_regclass('public.admob_reward_attempts') is null
    or to_regclass('public.admob_reward_transactions') is null
    or to_regprocedure('public.get_thread_balance(uuid)') is null
    or to_regprocedure('public.consume_fit_analysis_thread(uuid,uuid,uuid)') is null
    or to_regprocedure('public.create_fit_analysis_result_and_consume_thread(uuid,uuid,jsonb)') is null
    or to_regprocedure('public.consume_fit_report_thread(uuid,uuid,uuid)') is null
    or to_regprocedure('public.create_admob_reward_attempt(uuid)') is null
    or to_regprocedure('public.grant_admob_reward(uuid,text)') is null then
    raise exception using
      errcode = '55000',
      message = 'monetization_catalog_drift',
      detail = 'core_monetization_prerequisite_mismatch';
  end if;

  select pg_get_functiondef('public.grant_admob_reward(uuid,text)'::regprocedure)
  into grant_admob_definition;
  normalized_grant_admob_definition :=
    regexp_replace(lower(grant_admob_definition), '[[:space:]]+', '', 'g');

  core_catalog_valid :=
    (
      select count(*) = 4 and bool_and(c.relrowsecurity)
      from pg_class c
      where c.oid in (
        'public.thread_balances'::regclass,
        'public.thread_ledger_entries'::regclass,
        'public.admob_reward_attempts'::regclass,
        'public.admob_reward_transactions'::regclass
      )
    )
    and exists (
      select 1 from pg_constraint constraint_row
      where constraint_row.conrelid = 'public.thread_ledger_entries'::regclass
        and constraint_row.conname = 'thread_ledger_entries_reason_check'
        and pg_get_constraintdef(constraint_row.oid) =
          'CHECK ((reason = ANY (ARRAY[''fit_analysis''::text, ''fit_report''::text, ''iap_purchase''::text, ''ad_reward''::text, ''admin_adjustment''::text])))'
    )
    and exists (
      select 1 from pg_constraint constraint_row
      where constraint_row.conrelid = 'public.thread_ledger_entries'::regclass
        and constraint_row.conname = 'thread_ledger_entries_user_id_idempotency_key_reason_key'
        and pg_get_constraintdef(constraint_row.oid) = 'UNIQUE (user_id, idempotency_key, reason)'
    )
    and not exists (
      select 1 from pg_constraint constraint_row
      where constraint_row.conrelid = 'public.thread_ledger_entries'::regclass
        and constraint_row.conname = 'thread_ledger_entries_user_id_idempotency_key_key'
    )
    and exists (
      select 1 from pg_constraint constraint_row
      where constraint_row.conrelid = 'public.admob_reward_attempts'::regclass
        and constraint_row.conname = 'admob_reward_attempts_status_check'
        and pg_get_constraintdef(constraint_row.oid) =
          'CHECK ((status = ANY (ARRAY[''pending''::text, ''granted''::text, ''expired''::text])))'
    )
    and exists (
      select 1
      from pg_attribute attribute_row
      join pg_attrdef default_row
        on default_row.adrelid = attribute_row.attrelid
        and default_row.adnum = attribute_row.attnum
      where attribute_row.attrelid = 'public.admob_reward_attempts'::regclass
        and attribute_row.attname = 'expires_at'
        and pg_get_expr(default_row.adbin, default_row.adrelid) =
          '(now() + ''00:15:00''::interval)'
    )
    and exists (
      select 1 from pg_constraint constraint_row
      where constraint_row.conrelid = 'public.admob_reward_transactions'::regclass
        and constraint_row.conname = 'admob_reward_transactions_pkey'
        and pg_get_constraintdef(constraint_row.oid) = 'PRIMARY KEY (transaction_id)'
    )
    and exists (
      select 1 from pg_constraint constraint_row
      where constraint_row.conrelid = 'public.admob_reward_transactions'::regclass
        and constraint_row.conname = 'admob_reward_transactions_attempt_id_key'
        and pg_get_constraintdef(constraint_row.oid) = 'UNIQUE (attempt_id)'
    )
    and has_function_privilege('service_role', 'public.grant_admob_reward(uuid,text)', 'execute')
    and not has_function_privilege('anon', 'public.grant_admob_reward(uuid,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.grant_admob_reward(uuid,text)', 'execute');

  stale_admob_valid :=
    position(
      regexp_replace(stale_admob_declaration_fragment, '[[:space:]]+', '', 'g')
      in normalized_grant_admob_definition
    ) > 0
    and position(
      regexp_replace(stale_admob_replay_fragment, '[[:space:]]+', '', 'g')
      in normalized_grant_admob_definition
    ) > 0
    and position('admob_transaction_attempt_conflict' in grant_admob_definition) = 0;

  hardened_admob_valid :=
    position('admob_transaction_attempt_conflict' in grant_admob_definition) > 0
    and position('admob_attempt_transaction_conflict' in grant_admob_definition) > 0
    and position('admob_transaction_id_required' in grant_admob_definition) > 0;

  apple_absent :=
    to_regclass('public.apple_iap_transactions') is null
    and to_regclass('public.apple_iap_notification_receipts') is null
    and not exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'thread_ledger_entries'
        and column_name = 'apple_iap_transaction_id'
    )
    and to_regclass('public.idx_thread_ledger_entries_apple_iap_transaction') is null
    and to_regprocedure(
      'public.grant_apple_iap_threads(uuid,text,text,text,uuid,timestamptz,text,integer)'
    ) is null
    and to_regprocedure('public.record_apple_iap_notification(uuid,text,text,text)') is null
    and to_regprocedure(
      'public.reconcile_apple_iap_notification(uuid,text,text,text,uuid,text,text,text,uuid,timestamptz,text,integer)'
    ) is null;

  if to_regclass('public.apple_iap_transactions') is not null
    and to_regclass('public.apple_iap_notification_receipts') is not null
    and to_regprocedure(
      'public.grant_apple_iap_threads(uuid,text,text,text,uuid,timestamptz,text,integer)'
    ) is not null
    and to_regprocedure('public.record_apple_iap_notification(uuid,text,text,text)') is not null
    and to_regprocedure(
      'public.reconcile_apple_iap_notification(uuid,text,text,text,uuid,text,text,text,uuid,timestamptz,text,integer)'
    ) is not null then
    select pg_get_functiondef(
      'public.grant_apple_iap_threads(uuid,text,text,text,uuid,timestamptz,text,integer)'::regprocedure
    ) into grant_apple_definition;
    select pg_get_functiondef(
      'public.record_apple_iap_notification(uuid,text,text,text)'::regprocedure
    ) into record_notification_definition;
    select pg_get_functiondef(
      'public.reconcile_apple_iap_notification(uuid,text,text,text,uuid,text,text,text,uuid,timestamptz,text,integer)'::regprocedure
    ) into reconcile_notification_definition;

    apple_exact :=
      (
        select count(*) = 9
        from information_schema.columns
        where table_schema = 'public' and table_name = 'apple_iap_transactions'
      )
      and not exists (
        select 1
        from (values
          ('id', 'uuid', 'NO'),
          ('transaction_id', 'text', 'NO'),
          ('original_transaction_id', 'text', 'NO'),
          ('user_id', 'uuid', 'NO'),
          ('product_id', 'text', 'NO'),
          ('app_account_token', 'uuid', 'NO'),
          ('purchased_at', 'timestamp with time zone', 'NO'),
          ('environment', 'text', 'NO'),
          ('created_at', 'timestamp with time zone', 'NO')
        ) expected(column_name, data_type, is_nullable)
        left join information_schema.columns actual
          on actual.table_schema = 'public'
          and actual.table_name = 'apple_iap_transactions'
          and actual.column_name = expected.column_name
        where actual.column_name is null
          or actual.data_type is distinct from expected.data_type
          or actual.is_nullable is distinct from expected.is_nullable
      )
      and (
        select count(*) = 6
        from information_schema.columns
        where table_schema = 'public' and table_name = 'apple_iap_notification_receipts'
      )
      and not exists (
        select 1
        from (values
          ('notification_uuid', 'uuid', 'NO'),
          ('notification_type', 'text', 'NO'),
          ('subtype', 'text', 'YES'),
          ('environment', 'text', 'NO'),
          ('apple_iap_transaction_id', 'uuid', 'YES'),
          ('processed_at', 'timestamp with time zone', 'NO')
        ) expected(column_name, data_type, is_nullable)
        left join information_schema.columns actual
          on actual.table_schema = 'public'
          and actual.table_name = 'apple_iap_notification_receipts'
          and actual.column_name = expected.column_name
        where actual.column_name is null
          or actual.data_type is distinct from expected.data_type
          or actual.is_nullable is distinct from expected.is_nullable
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.apple_iap_transactions'::regclass
          and pg_get_constraintdef(constraint_row.oid) = 'PRIMARY KEY (id)'
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.apple_iap_transactions'::regclass
          and pg_get_constraintdef(constraint_row.oid) = 'UNIQUE (transaction_id)'
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.apple_iap_transactions'::regclass
          and pg_get_constraintdef(constraint_row.oid) =
            'FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE'
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.apple_iap_transactions'::regclass
          and pg_get_constraintdef(constraint_row.oid) = 'CHECK ((app_account_token = user_id))'
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.apple_iap_transactions'::regclass
          and pg_get_constraintdef(constraint_row.oid) =
            'CHECK ((environment = ANY (ARRAY[''Sandbox''::text, ''Production''::text])))'
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.apple_iap_notification_receipts'::regclass
          and pg_get_constraintdef(constraint_row.oid) = 'PRIMARY KEY (notification_uuid)'
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.apple_iap_notification_receipts'::regclass
          and pg_get_constraintdef(constraint_row.oid) =
            'FOREIGN KEY (apple_iap_transaction_id) REFERENCES apple_iap_transactions(id) ON DELETE RESTRICT'
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.apple_iap_notification_receipts'::regclass
          and pg_get_constraintdef(constraint_row.oid) =
            'CHECK ((environment = ANY (ARRAY[''Sandbox''::text, ''Production''::text])))'
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.apple_iap_notification_receipts'::regclass
          and pg_get_constraintdef(constraint_row.oid) =
            'CHECK ((btrim(notification_type) <> ''''::text))'
      )
      and exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'thread_ledger_entries'
          and column_name = 'apple_iap_transaction_id'
          and data_type = 'uuid'
          and is_nullable = 'YES'
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.thread_ledger_entries'::regclass
          and pg_get_constraintdef(constraint_row.oid) =
            'FOREIGN KEY (apple_iap_transaction_id) REFERENCES apple_iap_transactions(id) ON DELETE CASCADE'
      )
      and to_regclass('public.idx_thread_ledger_entries_apple_iap_transaction') is not null
      and pg_get_indexdef('public.idx_thread_ledger_entries_apple_iap_transaction'::regclass) =
        'CREATE UNIQUE INDEX idx_thread_ledger_entries_apple_iap_transaction ON public.thread_ledger_entries USING btree (apple_iap_transaction_id) WHERE (apple_iap_transaction_id IS NOT NULL)'
      and (
        select count(*) = 2 and bool_and(c.relrowsecurity)
        from pg_class c
        where c.oid in (
          'public.apple_iap_transactions'::regclass,
          'public.apple_iap_notification_receipts'::regclass
        )
      )
      and position('apple_product_amount_invalid' in grant_apple_definition) > 0
      and position('apple_transaction_metadata_conflict' in grant_apple_definition) > 0
      and position('apple_notification_reconciliation_required' in record_notification_definition) > 0
      and position('apple_notification_metadata_conflict' in record_notification_definition) > 0
      and position('already_processed' in reconcile_notification_definition) > 0
      and has_function_privilege(
        'service_role',
        'public.reconcile_apple_iap_notification(uuid,text,text,text,uuid,text,text,text,uuid,timestamptz,text,integer)',
        'execute'
      )
      and not has_function_privilege(
        'anon',
        'public.reconcile_apple_iap_notification(uuid,text,text,text,uuid,text,text,text,uuid,timestamptz,text,integer)',
        'execute'
      )
      and not has_function_privilege(
        'authenticated',
        'public.reconcile_apple_iap_notification(uuid,text,text,text,uuid,text,text,text,uuid,timestamptz,text,integer)',
        'execute'
      );
  end if;

  markers_absent := to_regclass('public.coordit_monetization_schema_versions') is null;
  if not markers_absent then
    markers_exact :=
      (
        select count(*) = 3
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'coordit_monetization_schema_versions'
      )
      and not exists (
        select 1
        from (values
          ('component', 'text', 'NO'),
          ('version', 'integer', 'NO'),
          ('installed_at', 'timestamp with time zone', 'NO')
        ) expected(column_name, data_type, is_nullable)
        left join information_schema.columns actual
          on actual.table_schema = 'public'
          and actual.table_name = 'coordit_monetization_schema_versions'
          and actual.column_name = expected.column_name
        where actual.column_name is null
          or actual.data_type is distinct from expected.data_type
          or actual.is_nullable is distinct from expected.is_nullable
      )
      and (
        select c.relrowsecurity
        from pg_class c
        where c.oid = 'public.coordit_monetization_schema_versions'::regclass
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.coordit_monetization_schema_versions'::regclass
          and constraint_row.conname = 'coordit_monetization_schema_versions_pkey'
          and pg_get_constraintdef(constraint_row.oid) = 'PRIMARY KEY (component)'
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.coordit_monetization_schema_versions'::regclass
          and constraint_row.conname = 'coordit_monetization_schema_versions_component_check'
          and pg_get_constraintdef(constraint_row.oid) =
            'CHECK ((btrim(component) <> ''''::text))'
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.coordit_monetization_schema_versions'::regclass
          and constraint_row.conname = 'coordit_monetization_schema_versions_version_check'
          and pg_get_constraintdef(constraint_row.oid) = 'CHECK ((version > 0))'
      )
      and (
        select count(*) = 5
        from public.coordit_monetization_schema_versions
      )
      and (
        select count(*) = 5
        from public.coordit_monetization_schema_versions
        where (component, version) in (
          ('wallet', 1),
          ('admob_reward', 2),
          ('apple_iap', 2),
          ('apple_notifications', 2),
          ('release_reconciliation', 20260822)
        )
      );
  end if;

  records_absent := to_regclass('public.coordit_schema_change_records') is null;
  if not records_absent then
    record_table_exact :=
      (
        select count(*) = 5
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'coordit_schema_change_records'
      )
      and not exists (
        select 1
        from (values
          ('migration_version', 'text', 'NO'),
          ('migration_filename', 'text', 'NO'),
          ('migration_sha256', 'text', 'NO'),
          ('disposition', 'text', 'NO'),
          ('applied_at', 'timestamp with time zone', 'NO')
        ) expected(column_name, data_type, is_nullable)
        left join information_schema.columns actual
          on actual.table_schema = 'public'
          and actual.table_name = 'coordit_schema_change_records'
          and actual.column_name = expected.column_name
        where actual.column_name is null
          or actual.data_type is distinct from expected.data_type
          or actual.is_nullable is distinct from expected.is_nullable
      )
      and (
        select c.relrowsecurity
        from pg_class c
        where c.oid = 'public.coordit_schema_change_records'::regclass
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.coordit_schema_change_records'::regclass
          and constraint_row.conname = 'coordit_schema_change_records_pkey'
          and pg_get_constraintdef(constraint_row.oid) = 'PRIMARY KEY (migration_version)'
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.coordit_schema_change_records'::regclass
          and constraint_row.conname = 'coordit_schema_change_records_migration_filename_key'
          and pg_get_constraintdef(constraint_row.oid) = 'UNIQUE (migration_filename)'
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.coordit_schema_change_records'::regclass
          and constraint_row.conname = 'coordit_schema_change_records_migration_version_check'
          and pg_get_constraintdef(constraint_row.oid) =
            'CHECK ((migration_version ~ ''^[0-9]{8}$''::text))'
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.coordit_schema_change_records'::regclass
          and constraint_row.conname = 'coordit_schema_change_records_migration_filename_check'
          and pg_get_constraintdef(constraint_row.oid) =
            'CHECK ((btrim(migration_filename) <> ''''::text))'
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.coordit_schema_change_records'::regclass
          and constraint_row.conname = 'coordit_schema_change_records_migration_sha256_check'
          and pg_get_constraintdef(constraint_row.oid) =
            'CHECK ((migration_sha256 ~ ''^[0-9a-f]{64}$''::text))'
      )
      and exists (
        select 1 from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.coordit_schema_change_records'::regclass
          and constraint_row.conname = 'coordit_schema_change_records_disposition_check'
          and pg_get_constraintdef(constraint_row.oid) =
            'CHECK ((disposition = ANY (ARRAY[''reconciled_observed_partial''::text, ''verified_exact_target''::text])))'
      )
      and has_table_privilege(
        'service_role',
        'public.coordit_schema_change_records',
        'select'
      )
      and not (
        has_table_privilege('service_role', 'public.coordit_schema_change_records', 'insert')
        or has_table_privilege('service_role', 'public.coordit_schema_change_records', 'update')
        or has_table_privilege('service_role', 'public.coordit_schema_change_records', 'delete')
        or has_table_privilege('service_role', 'public.coordit_schema_change_records', 'truncate')
        or has_table_privilege('service_role', 'public.coordit_schema_change_records', 'references')
        or has_table_privilege('service_role', 'public.coordit_schema_change_records', 'trigger')
      );

    if not record_table_exact then
      raise exception using
        errcode = '55000',
        message = 'monetization_catalog_drift',
        detail = 'change_record_table_fingerprint_mismatch';
    end if;

    if exists (
      select 1
      from public.coordit_schema_change_records record
      where record.migration_version = '20260822'
        and (
          record.migration_filename is distinct from runner_filename
          or record.migration_sha256 is distinct from runner_sha256
          or record.disposition not in ('reconciled_observed_partial', 'verified_exact_target')
        )
    ) then
      raise exception using
        errcode = '55000',
        message = 'monetization_schema_change_record_conflict';
    end if;

    select record.disposition
    into recorded_disposition
    from public.coordit_schema_change_records record
    where record.migration_version = '20260822';

    records_exact := recorded_disposition in (
      'reconciled_observed_partial',
      'verified_exact_target'
    );
  end if;

  if core_catalog_valid
    and stale_admob_valid
    and apple_absent
    and markers_absent
    and records_absent then
    perform set_config(
      'coordit.reconciliation_disposition',
      'reconciled_observed_partial',
      true
    );
  elsif core_catalog_valid
    and hardened_admob_valid
    and apple_exact
    and (
      (markers_absent and records_absent)
      or (markers_exact and records_exact)
    ) then
    perform set_config(
      'coordit.reconciliation_disposition',
      coalesce(recorded_disposition, 'verified_exact_target'),
      true
    );
  else
    raise exception using
      errcode = '55000',
      message = 'monetization_catalog_drift',
      detail = 'state_is_neither_observed_partial_nor_exact_target';
  end if;
end;
$$;

do $$
declare
  missing_tables text;
begin
  select string_agg(required_table, ', ' order by required_table)
  into missing_tables
  from unnest(array[
    'public.users',
    'public.fit_analysis_results',
    'public.thread_balances',
    'public.thread_ledger_entries',
    'public.admob_reward_attempts',
    'public.admob_reward_transactions'
  ]) required(required_table)
  where to_regclass(required_table) is null;

  if missing_tables is not null then
    raise exception using
      errcode = '55000',
      message = 'monetization_prerequisite_missing',
      detail = format('Required tables are absent: %s', missing_tables);
  end if;
end;
$$;

alter table public.thread_ledger_entries
  drop constraint if exists thread_ledger_entries_reason_check;
alter table public.thread_ledger_entries
  add constraint thread_ledger_entries_reason_check
  check (reason in ('fit_analysis', 'fit_report', 'iap_purchase', 'ad_reward', 'admin_adjustment'));

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

create table if not exists public.apple_iap_notification_receipts (
  notification_uuid uuid primary key,
  notification_type text not null check (btrim(notification_type) <> ''),
  subtype text,
  environment text not null check (environment in ('Sandbox', 'Production')),
  apple_iap_transaction_id uuid
    references public.apple_iap_transactions(id) on delete restrict,
  processed_at timestamptz not null default now()
);

create table if not exists public.coordit_monetization_schema_versions (
  component text primary key check (btrim(component) <> ''),
  version integer not null check (version > 0),
  installed_at timestamptz not null default now()
);

create table if not exists public.coordit_schema_change_records (
  migration_version text primary key
    check (migration_version ~ '^[0-9]{8}$'),
  migration_filename text not null unique
    check (btrim(migration_filename) <> ''),
  migration_sha256 text not null
    check (migration_sha256 ~ '^[0-9a-f]{64}$'),
  disposition text not null
    check (disposition in ('reconciled_observed_partial', 'verified_exact_target')),
  applied_at timestamptz not null default now()
);

lock table public.coordit_schema_change_records in share row exclusive mode;

do $$
begin
  if exists (
    select 1
    from (values
      ('id', 'uuid', 'NO'),
      ('transaction_id', 'text', 'NO'),
      ('original_transaction_id', 'text', 'NO'),
      ('user_id', 'uuid', 'NO'),
      ('product_id', 'text', 'NO'),
      ('app_account_token', 'uuid', 'NO'),
      ('purchased_at', 'timestamp with time zone', 'NO'),
      ('environment', 'text', 'NO'),
      ('created_at', 'timestamp with time zone', 'NO')
    ) expected(column_name, data_type, is_nullable)
    left join information_schema.columns actual
      on actual.table_schema = 'public'
      and actual.table_name = 'apple_iap_transactions'
      and actual.column_name = expected.column_name
    where actual.column_name is null
      or actual.data_type is distinct from expected.data_type
      or actual.is_nullable is distinct from expected.is_nullable
  ) then
    raise exception using
      errcode = '55000',
      message = 'apple_iap_transactions_schema_incompatible';
  end if;

  if exists (
    select 1
    from (values
      ('notification_uuid', 'uuid', 'NO'),
      ('notification_type', 'text', 'NO'),
      ('subtype', 'text', 'YES'),
      ('environment', 'text', 'NO'),
      ('apple_iap_transaction_id', 'uuid', 'YES'),
      ('processed_at', 'timestamp with time zone', 'NO')
    ) expected(column_name, data_type, is_nullable)
    left join information_schema.columns actual
      on actual.table_schema = 'public'
      and actual.table_name = 'apple_iap_notification_receipts'
      and actual.column_name = expected.column_name
    where actual.column_name is null
      or actual.data_type is distinct from expected.data_type
      or actual.is_nullable is distinct from expected.is_nullable
  ) then
    raise exception using
      errcode = '55000',
      message = 'apple_iap_notification_receipts_schema_incompatible';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'thread_ledger_entries'
      and column_name = 'apple_iap_transaction_id'
      and data_type = 'uuid'
      and is_nullable = 'YES'
  ) then
    raise exception using
      errcode = '55000',
      message = 'thread_ledger_apple_reference_incompatible';
  end if;
end;
$$;

alter table public.thread_balances enable row level security;
alter table public.thread_ledger_entries enable row level security;
alter table public.admob_reward_attempts enable row level security;
alter table public.admob_reward_transactions enable row level security;
alter table public.apple_iap_transactions enable row level security;
alter table public.apple_iap_notification_receipts enable row level security;
alter table public.coordit_monetization_schema_versions enable row level security;
alter table public.coordit_schema_change_records enable row level security;

revoke all on table
  public.thread_balances,
  public.thread_ledger_entries,
  public.admob_reward_attempts,
  public.admob_reward_transactions,
  public.apple_iap_transactions,
  public.apple_iap_notification_receipts,
  public.coordit_monetization_schema_versions,
  public.coordit_schema_change_records
from public, anon, authenticated;

revoke all on table public.coordit_schema_change_records from service_role;
grant select on table public.coordit_schema_change_records to service_role;

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
language plpgsql
security definer
set search_path = public
as $$
declare
  current_balance integer;
  iap_transaction_id uuid;
  existing_transaction public.apple_iap_transactions%rowtype;
  expected_thread_amount integer;
begin
  if p_transaction_id is null or btrim(p_transaction_id) = '' then
    raise exception using errcode = '22023', message = 'apple_transaction_id_required';
  end if;
  if p_original_transaction_id is null or btrim(p_original_transaction_id) = '' then
    raise exception using errcode = '22023', message = 'apple_original_transaction_id_required';
  end if;
  if p_purchased_at is null then
    raise exception using errcode = '22023', message = 'apple_purchase_date_required';
  end if;

  expected_thread_amount := case p_product_id
    when 'com.inseong.coordit.thread.5' then 5
    when 'com.inseong.coordit.thread.10' then 10
    when 'com.inseong.coordit.thread.20' then 20
    else null
  end;
  if expected_thread_amount is null or p_thread_amount is distinct from expected_thread_amount then
    raise exception using errcode = '22023', message = 'apple_product_amount_invalid';
  end if;
  if p_environment not in ('Sandbox', 'Production') then
    raise exception using errcode = '22023', message = 'apple_environment_invalid';
  end if;
  if p_app_account_token is distinct from p_user_id then
    raise exception using errcode = '42501', message = 'apple_transaction_account_mismatch';
  end if;

  insert into public.thread_balances(user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  select balance.available_threads
  into current_balance
  from public.thread_balances balance
  where balance.user_id = p_user_id
  for update;

  select transaction.*
  into existing_transaction
  from public.apple_iap_transactions transaction
  where transaction.transaction_id = p_transaction_id
  for update;

  if found then
    if existing_transaction.user_id is distinct from p_user_id
      or existing_transaction.original_transaction_id is distinct from p_original_transaction_id
      or existing_transaction.product_id is distinct from p_product_id
      or existing_transaction.app_account_token is distinct from p_app_account_token
      or existing_transaction.purchased_at is distinct from p_purchased_at
      or existing_transaction.environment is distinct from p_environment then
      raise exception using errcode = '23505', message = 'apple_transaction_metadata_conflict';
    end if;
    return query select current_balance, 'already_credited'::text;
    return;
  end if;

  begin
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
    returning id into iap_transaction_id;
  exception
    when unique_violation then
      select transaction.*
      into existing_transaction
      from public.apple_iap_transactions transaction
      where transaction.transaction_id = p_transaction_id
      for update;

      if not found
        or existing_transaction.user_id is distinct from p_user_id
        or existing_transaction.original_transaction_id is distinct from p_original_transaction_id
        or existing_transaction.product_id is distinct from p_product_id
        or existing_transaction.app_account_token is distinct from p_app_account_token
        or existing_transaction.purchased_at is distinct from p_purchased_at
        or existing_transaction.environment is distinct from p_environment then
        raise exception using errcode = '23505', message = 'apple_transaction_metadata_conflict';
      end if;
      return query select current_balance, 'already_credited'::text;
      return;
  end;

  update public.thread_balances balance
  set available_threads = balance.available_threads + expected_thread_amount,
      updated_at = now()
  where balance.user_id = p_user_id
  returning balance.available_threads into current_balance;

  insert into public.thread_ledger_entries(
    user_id,
    idempotency_key,
    amount,
    reason,
    apple_iap_transaction_id
  ) values (
    p_user_id,
    iap_transaction_id,
    expected_thread_amount,
    'iap_purchase',
    iap_transaction_id
  );

  return query select current_balance, 'credited'::text;
end;
$$;

create or replace function public.record_apple_iap_notification(
  p_notification_uuid uuid,
  p_notification_type text,
  p_subtype text,
  p_environment text
)
returns table(status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted_count integer;
  existing_receipt public.apple_iap_notification_receipts%rowtype;
begin
  if p_notification_type is null or btrim(p_notification_type) = '' then
    raise exception using errcode = '22023', message = 'apple_notification_type_required';
  end if;
  if p_notification_type = 'ONE_TIME_CHARGE' then
    raise exception using errcode = '22023', message = 'apple_notification_reconciliation_required';
  end if;
  if p_environment not in ('Sandbox', 'Production') then
    raise exception using errcode = '22023', message = 'apple_notification_environment_invalid';
  end if;

  insert into public.apple_iap_notification_receipts(
    notification_uuid,
    notification_type,
    subtype,
    environment
  ) values (
    p_notification_uuid,
    p_notification_type,
    p_subtype,
    p_environment
  )
  on conflict (notification_uuid) do nothing;
  get diagnostics inserted_count = row_count;

  if inserted_count = 1 then
    return query select 'processed'::text;
    return;
  end if;

  select receipt.*
  into existing_receipt
  from public.apple_iap_notification_receipts receipt
  where receipt.notification_uuid = p_notification_uuid
  for update;

  if existing_receipt.notification_type is distinct from p_notification_type
    or existing_receipt.subtype is distinct from p_subtype
    or existing_receipt.environment is distinct from p_environment
    or existing_receipt.apple_iap_transaction_id is not null then
    raise exception using errcode = '23505', message = 'apple_notification_metadata_conflict';
  end if;

  return query select 'already_processed'::text;
end;
$$;

create or replace function public.reconcile_apple_iap_notification(
  p_notification_uuid uuid,
  p_notification_type text,
  p_subtype text,
  p_environment text,
  p_user_id uuid,
  p_transaction_id text,
  p_original_transaction_id text,
  p_product_id text,
  p_app_account_token uuid,
  p_purchased_at timestamptz,
  p_transaction_environment text,
  p_thread_amount integer
)
returns table(available_threads integer, status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  credit_result record;
  iap_transaction_id uuid;
  inserted_count integer;
  existing_receipt public.apple_iap_notification_receipts%rowtype;
begin
  if p_notification_type is distinct from 'ONE_TIME_CHARGE' then
    raise exception using errcode = '22023', message = 'apple_notification_type_invalid';
  end if;
  if p_environment is distinct from p_transaction_environment then
    raise exception using errcode = '22023', message = 'apple_notification_environment_mismatch';
  end if;

  select grant_result.available_threads, grant_result.status
  into credit_result
  from public.grant_apple_iap_threads(
    p_user_id,
    p_transaction_id,
    p_original_transaction_id,
    p_product_id,
    p_app_account_token,
    p_purchased_at,
    p_transaction_environment,
    p_thread_amount
  ) grant_result;

  select transaction.id
  into iap_transaction_id
  from public.apple_iap_transactions transaction
  where transaction.transaction_id = p_transaction_id;

  insert into public.apple_iap_notification_receipts(
    notification_uuid,
    notification_type,
    subtype,
    environment,
    apple_iap_transaction_id
  ) values (
    p_notification_uuid,
    p_notification_type,
    p_subtype,
    p_environment,
    iap_transaction_id
  )
  on conflict (notification_uuid) do nothing;
  get diagnostics inserted_count = row_count;

  if inserted_count = 1 then
    return query select credit_result.available_threads, credit_result.status::text;
    return;
  end if;

  select receipt.*
  into existing_receipt
  from public.apple_iap_notification_receipts receipt
  where receipt.notification_uuid = p_notification_uuid
  for update;

  if existing_receipt.notification_type is distinct from p_notification_type
    or existing_receipt.subtype is distinct from p_subtype
    or existing_receipt.environment is distinct from p_environment
    or existing_receipt.apple_iap_transaction_id is distinct from iap_transaction_id then
    raise exception using errcode = '23505', message = 'apple_notification_metadata_conflict';
  end if;

  return query select credit_result.available_threads, 'already_processed'::text;
end;
$$;

revoke all on function public.get_thread_balance(uuid)
  from public, anon, authenticated;
revoke all on function public.consume_fit_analysis_thread(uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.create_fit_analysis_result_and_consume_thread(uuid, uuid, jsonb)
  from public, anon, authenticated;
revoke all on function public.consume_fit_report_thread(uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.create_admob_reward_attempt(uuid)
  from public, anon, authenticated;
revoke all on function public.grant_admob_reward(uuid, text)
  from public, anon, authenticated;
revoke all on function public.grant_apple_iap_threads(
  uuid, text, text, text, uuid, timestamptz, text, integer
) from public, anon, authenticated;
revoke all on function public.record_apple_iap_notification(uuid, text, text, text)
  from public, anon, authenticated;
revoke all on function public.reconcile_apple_iap_notification(
  uuid, text, text, text, uuid, text, text, text, uuid, timestamptz, text, integer
) from public, anon, authenticated;

grant execute on function public.get_thread_balance(uuid) to service_role;
grant execute on function public.consume_fit_analysis_thread(uuid, uuid, uuid) to service_role;
grant execute on function public.create_fit_analysis_result_and_consume_thread(uuid, uuid, jsonb)
  to service_role;
grant execute on function public.consume_fit_report_thread(uuid, uuid, uuid) to service_role;
grant execute on function public.create_admob_reward_attempt(uuid) to service_role;
grant execute on function public.grant_admob_reward(uuid, text) to service_role;
grant execute on function public.grant_apple_iap_threads(
  uuid, text, text, text, uuid, timestamptz, text, integer
) to service_role;
grant execute on function public.record_apple_iap_notification(uuid, text, text, text)
  to service_role;
grant execute on function public.reconcile_apple_iap_notification(
  uuid, text, text, text, uuid, text, text, text, uuid, timestamptz, text, integer
) to service_role;

do $$
begin
  if exists (
    select 1
    from (values
      ('wallet', 1),
      ('admob_reward', 2),
      ('apple_iap', 2),
      ('apple_notifications', 2),
      ('release_reconciliation', 20260822)
    ) expected(component, version)
    join public.coordit_monetization_schema_versions actual using (component)
    where actual.version is distinct from expected.version
  ) then
    raise exception using
      errcode = '55000',
      message = 'monetization_schema_version_conflict';
  end if;
end;
$$;

insert into public.coordit_monetization_schema_versions(component, version)
values
  ('wallet', 1),
  ('admob_reward', 2),
  ('apple_iap', 2),
  ('apple_notifications', 2),
  ('release_reconciliation', 20260822)
on conflict (component) do nothing;

insert into public.coordit_schema_change_records(
  migration_version,
  migration_filename,
  migration_sha256,
  disposition
) values (
  '20260822',
  current_setting('coordit.reconciliation_filename'),
  current_setting('coordit.reconciliation_sha256'),
  current_setting('coordit.reconciliation_disposition')
)
on conflict (migration_version) do nothing;
