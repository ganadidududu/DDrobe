-- allow: SIZE_OK — one forward migration owns the atomic profile/styling fingerprint and repair.

do $$
declare
  runner_filename text := current_setting(
    'coordit.profile_styling_reconciliation_filename',
    true
  );
  runner_sha256 text := current_setting(
    'coordit.profile_styling_reconciliation_sha256',
    true
  );
begin
  if runner_filename is distinct from
      '20260824_reconcile_profile_styling_schema.sql'
    or runner_sha256 is null
    or runner_sha256 !~ '^[0-9a-f]{64}$'
    or current_setting(
      'coordit.profile_styling_reconciliation_lock_acquired',
      true
    ) is distinct from 'on'
    or current_setting('lock_timeout') not in ('5s', '5000ms')
    or current_setting('statement_timeout') not in ('30s', '30000ms') then
    raise exception using
      errcode = '55000',
      message = 'profile_styling_reconciliation_runner_context_required';
  end if;

  if to_regclass('supabase_migrations.schema_migrations') is not null then
    raise exception using
      errcode = '55000',
      message = 'profile_styling_catalog_drift',
      detail = 'unexpected_supabase_migration_ledger';
  end if;

  if to_regclass('public.users') is null
    or to_regclass('public.coordit_schema_change_records') is null then
    raise exception using
      errcode = '55000',
      message = 'profile_styling_catalog_drift',
      detail = 'required_release_schema_absent';
  end if;
end;
$$;

lock table public.coordit_schema_change_records in share row exclusive mode;
lock table public.users in share update exclusive mode;

do $$
begin
  if to_regclass('public.styling_looks') is not null then
    execute 'lock table public.styling_looks in share update exclusive mode';
  end if;
end;
$$;

do $$
declare
  runner_filename text := current_setting(
    'coordit.profile_styling_reconciliation_filename'
  );
  runner_sha256 text := current_setting(
    'coordit.profile_styling_reconciliation_sha256'
  );
  birth_date_absent boolean := false;
  birth_date_exact boolean := false;
  styling_looks_absent boolean := false;
  styling_looks_exact boolean := false;
  record_table_exact boolean := false;
  recorded_disposition text;
begin
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
      select catalog.relrowsecurity
      from pg_class catalog
      where catalog.oid = 'public.coordit_schema_change_records'::regclass
    )
    and exists (
      select 1
      from pg_constraint constraint_row
      where constraint_row.conrelid =
          'public.coordit_schema_change_records'::regclass
        and constraint_row.conname = 'coordit_schema_change_records_pkey'
        and pg_get_constraintdef(constraint_row.oid) =
          'PRIMARY KEY (migration_version)'
    )
    and exists (
      select 1
      from pg_constraint constraint_row
      where constraint_row.conrelid =
          'public.coordit_schema_change_records'::regclass
        and constraint_row.conname =
          'coordit_schema_change_records_migration_filename_key'
        and pg_get_constraintdef(constraint_row.oid) =
          'UNIQUE (migration_filename)'
    )
    and exists (
      select 1
      from pg_constraint constraint_row
      where constraint_row.conrelid =
          'public.coordit_schema_change_records'::regclass
        and constraint_row.conname =
          'coordit_schema_change_records_migration_version_check'
        and pg_get_constraintdef(constraint_row.oid) =
          'CHECK ((migration_version ~ ''^[0-9]{8}$''::text))'
    )
    and exists (
      select 1
      from pg_constraint constraint_row
      where constraint_row.conrelid =
          'public.coordit_schema_change_records'::regclass
        and constraint_row.conname =
          'coordit_schema_change_records_migration_filename_check'
        and pg_get_constraintdef(constraint_row.oid) =
          'CHECK ((btrim(migration_filename) <> ''''::text))'
    )
    and exists (
      select 1
      from pg_constraint constraint_row
      where constraint_row.conrelid =
          'public.coordit_schema_change_records'::regclass
        and constraint_row.conname =
          'coordit_schema_change_records_migration_sha256_check'
        and pg_get_constraintdef(constraint_row.oid) =
          'CHECK ((migration_sha256 ~ ''^[0-9a-f]{64}$''::text))'
    )
    and exists (
      select 1
      from pg_constraint constraint_row
      where constraint_row.conrelid =
          'public.coordit_schema_change_records'::regclass
        and constraint_row.conname =
          'coordit_schema_change_records_disposition_check'
        and pg_get_constraintdef(constraint_row.oid) =
          'CHECK ((disposition = ANY (ARRAY[''reconciled_observed_partial''::text, ''verified_exact_target''::text])))'
    )
    and has_table_privilege(
      'service_role',
      'public.coordit_schema_change_records',
      'select'
    )
    and not (
      has_table_privilege(
        'service_role',
        'public.coordit_schema_change_records',
        'insert'
      )
      or has_table_privilege(
        'service_role',
        'public.coordit_schema_change_records',
        'update'
      )
      or has_table_privilege(
        'service_role',
        'public.coordit_schema_change_records',
        'delete'
      )
      or has_table_privilege(
        'service_role',
        'public.coordit_schema_change_records',
        'truncate'
      )
      or has_table_privilege(
        'service_role',
        'public.coordit_schema_change_records',
        'references'
      )
      or has_table_privilege(
        'service_role',
        'public.coordit_schema_change_records',
        'trigger'
      )
    );

  if not record_table_exact then
    raise exception using
      errcode = '55000',
      message = 'profile_styling_catalog_drift',
      detail = 'change_record_table_fingerprint_mismatch';
  end if;

  if to_regprocedure('gen_random_uuid()') is null
    or not exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'users'
        and column_name = 'id'
        and data_type = 'uuid'
        and is_nullable = 'NO'
    )
    or not exists (
      select 1
      from pg_constraint constraint_row
      where constraint_row.conrelid = 'public.users'::regclass
        and constraint_row.contype = 'p'
        and pg_get_constraintdef(constraint_row.oid) = 'PRIMARY KEY (id)'
    ) then
    raise exception using
      errcode = '55000',
      message = 'profile_styling_catalog_drift',
      detail = 'users_prerequisite_fingerprint_mismatch';
  end if;

  if not exists (
    select 1
    from public.coordit_schema_change_records record
    where record.migration_version = '20260822'
      and record.migration_filename =
        '20260822_reconcile_monetization_release_schema.sql'
      and record.migration_sha256 =
        '3cc70e8ddc56e4ca9a923bb368f144d84afe680a3bcddc7bae37e23595dc9233'
      and record.disposition in (
        'reconciled_observed_partial',
        'verified_exact_target'
      )
  ) then
    raise exception using
      errcode = '55000',
      message = 'profile_styling_catalog_drift',
      detail = 'required_monetization_receipt_mismatch';
  end if;

  if exists (
    select 1
    from public.coordit_schema_change_records record
    where (
      record.migration_version = '20260824'
      or record.migration_filename = runner_filename
    )
      and not (
        record.migration_version = '20260824'
        and record.migration_filename = runner_filename
        and record.migration_sha256 = runner_sha256
        and record.disposition in (
          'reconciled_observed_partial',
          'verified_exact_target'
        )
      )
  ) then
    raise exception using
      errcode = '55000',
      message = 'profile_styling_schema_change_record_conflict';
  end if;

  select record.disposition
  into recorded_disposition
  from public.coordit_schema_change_records record
  where record.migration_version = '20260824'
    and record.migration_filename = runner_filename
    and record.migration_sha256 = runner_sha256;

  birth_date_absent := not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'birth_date'
  );
  birth_date_exact := exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'birth_date'
      and data_type = 'date'
      and is_nullable = 'YES'
      and column_default is null
      and is_generated = 'NEVER'
  );

  styling_looks_absent := to_regclass('public.styling_looks') is null;

  if not styling_looks_absent then
    styling_looks_exact :=
      (
        select catalog.relkind = 'r'
          and catalog.relrowsecurity
          and not catalog.relforcerowsecurity
        from pg_class catalog
        where catalog.oid = 'public.styling_looks'::regclass
      )
      and (
        select count(*) = 11
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'styling_looks'
      )
      and not exists (
        select 1
        from (values
          ('id', 'uuid', 'NO', 'gen_random_uuid()'),
          ('user_id', 'uuid', 'NO', null),
          ('name', 'text', 'NO', null),
          ('name_ko', 'text', 'NO', null),
          ('mood', 'text', 'NO', '''''::text'),
          ('palette', 'jsonb', 'NO', '''[]''::jsonb'),
          ('ai_reasoning', 'text', 'NO', '''''::text'),
          ('fit_score', 'numeric', 'YES', null),
          ('item_ids', 'jsonb', 'NO', '''[]''::jsonb'),
          ('prompt', 'text', 'NO', '''''::text'),
          ('created_at', 'timestamp with time zone', 'NO', 'now()')
        ) expected(column_name, data_type, is_nullable, column_default)
        left join information_schema.columns actual
          on actual.table_schema = 'public'
          and actual.table_name = 'styling_looks'
          and actual.column_name = expected.column_name
        where actual.column_name is null
          or actual.data_type is distinct from expected.data_type
          or actual.is_nullable is distinct from expected.is_nullable
          or actual.column_default is distinct from expected.column_default
      )
      and exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'styling_looks'
          and column_name = 'fit_score'
          and numeric_precision = 5
          and numeric_scale = 2
      )
      and (
        select count(*) = 2
        from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.styling_looks'::regclass
          and constraint_row.contype <> 'n'
      )
      and exists (
        select 1
        from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.styling_looks'::regclass
          and constraint_row.conname = 'styling_looks_pkey'
          and pg_get_constraintdef(constraint_row.oid) = 'PRIMARY KEY (id)'
      )
      and exists (
        select 1
        from pg_constraint constraint_row
        where constraint_row.conrelid = 'public.styling_looks'::regclass
          and constraint_row.conname = 'styling_looks_user_id_fkey'
          and pg_get_constraintdef(constraint_row.oid) =
            'FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE'
      )
      and (
        select count(*) = 2
        from pg_index index_row
        where index_row.indrelid = 'public.styling_looks'::regclass
      )
      and exists (
        select 1
        from pg_index index_row
        join pg_class index_catalog on index_catalog.oid = index_row.indexrelid
        join pg_am access_method on access_method.oid = index_catalog.relam
        where index_row.indrelid = 'public.styling_looks'::regclass
          and index_catalog.relname = 'styling_looks_user_id_idx'
          and access_method.amname = 'btree'
          and not index_row.indisunique
          and index_row.indisvalid
          and index_row.indisready
          and index_row.indexprs is null
          and index_row.indpred is null
          and pg_get_indexdef(index_catalog.oid) =
            'CREATE INDEX styling_looks_user_id_idx ON public.styling_looks USING btree (user_id)'
      )
      and not exists (
        select 1
        from pg_policy policy_row
        where policy_row.polrelid = 'public.styling_looks'::regclass
      )
      and has_table_privilege(
        'service_role',
        'public.styling_looks',
        'select'
      )
      and has_table_privilege(
        'service_role',
        'public.styling_looks',
        'insert'
      )
      and has_table_privilege(
        'service_role',
        'public.styling_looks',
        'update'
      )
      and has_table_privilege(
        'service_role',
        'public.styling_looks',
        'delete'
      )
      and not (
        has_table_privilege('service_role', 'public.styling_looks', 'truncate')
        or has_table_privilege(
          'service_role',
          'public.styling_looks',
          'references'
        )
        or has_table_privilege('service_role', 'public.styling_looks', 'trigger')
      )
      and not (
        has_table_privilege('anon', 'public.styling_looks', 'select')
        or has_table_privilege('anon', 'public.styling_looks', 'insert')
        or has_table_privilege('anon', 'public.styling_looks', 'update')
        or has_table_privilege('anon', 'public.styling_looks', 'delete')
        or has_table_privilege('anon', 'public.styling_looks', 'truncate')
        or has_table_privilege('anon', 'public.styling_looks', 'references')
        or has_table_privilege('anon', 'public.styling_looks', 'trigger')
      )
      and not (
        has_table_privilege('authenticated', 'public.styling_looks', 'select')
        or has_table_privilege('authenticated', 'public.styling_looks', 'insert')
        or has_table_privilege('authenticated', 'public.styling_looks', 'update')
        or has_table_privilege('authenticated', 'public.styling_looks', 'delete')
        or has_table_privilege('authenticated', 'public.styling_looks', 'truncate')
        or has_table_privilege(
          'authenticated',
          'public.styling_looks',
          'references'
        )
        or has_table_privilege('authenticated', 'public.styling_looks', 'trigger')
      );
  end if;

  if birth_date_absent
    and styling_looks_absent
    and recorded_disposition is null then
    perform set_config(
      'coordit.profile_styling_reconciliation_disposition',
      'reconciled_observed_partial',
      true
    );
    perform set_config(
      'coordit.profile_styling_reconciliation_apply_required',
      'on',
      true
    );
  elsif birth_date_exact
    and styling_looks_exact
    and (
      recorded_disposition is null
      or recorded_disposition in (
        'reconciled_observed_partial',
        'verified_exact_target'
      )
    ) then
    perform set_config(
      'coordit.profile_styling_reconciliation_disposition',
      coalesce(recorded_disposition, 'verified_exact_target'),
      true
    );
    perform set_config(
      'coordit.profile_styling_reconciliation_apply_required',
      'off',
      true
    );
  else
    raise exception using
      errcode = '55000',
      message = 'profile_styling_catalog_drift',
      detail = 'state_is_neither_observed_partial_nor_exact_target';
  end if;
end;
$$;

do $$
begin
  if current_setting(
    'coordit.profile_styling_reconciliation_apply_required'
  ) = 'on' then
    execute 'alter table public.users add column birth_date date';
    execute $ddl$
      create table public.styling_looks (
        id uuid primary key default gen_random_uuid(),
        user_id uuid not null references public.users(id) on delete cascade,
        name text not null,
        name_ko text not null,
        mood text not null default '',
        palette jsonb not null default '[]'::jsonb,
        ai_reasoning text not null default '',
        fit_score numeric(5,2),
        item_ids jsonb not null default '[]'::jsonb,
        prompt text not null default '',
        created_at timestamptz not null default now()
      )
    $ddl$;
    execute $ddl$
      create index styling_looks_user_id_idx
      on public.styling_looks(user_id)
    $ddl$;
    execute 'alter table public.styling_looks enable row level security';
    execute $ddl$
      revoke all on table public.styling_looks
      from public, anon, authenticated, service_role
    $ddl$;
    execute $ddl$
      grant select, insert, update, delete on table public.styling_looks
      to service_role
    $ddl$;
  end if;
end;
$$;

insert into public.coordit_schema_change_records(
  migration_version,
  migration_filename,
  migration_sha256,
  disposition
) values (
  '20260824',
  current_setting('coordit.profile_styling_reconciliation_filename'),
  current_setting('coordit.profile_styling_reconciliation_sha256'),
  current_setting('coordit.profile_styling_reconciliation_disposition')
)
on conflict (migration_version) do nothing;
