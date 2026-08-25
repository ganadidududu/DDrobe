import { z } from "zod";

export const stylingSchemaFinalizationPostflightRowSchema = z.object({
  birth_date_exact: z.literal(true),
  change_record_exact: z.literal(true),
  ledger_absent: z.literal(true),
  monetary_receipt_exact: z.literal(true),
  receipt_20260824_absent: z.literal(true),
  styling_columns_exact: z.literal(true),
  styling_constraints_exact: z.literal(true),
  styling_index_exact: z.literal(true),
  styling_security_exact: z.literal(true)
});

export const stylingSchemaFinalizationPostflightSql = `
  select
    exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'users'
        and column_name = 'birth_date'
        and data_type = 'date'
        and is_nullable = 'YES'
        and column_default is null
        and is_generated = 'NEVER'
    ) as birth_date_exact,
    to_regclass('supabase_migrations.schema_migrations') is null as ledger_absent,
    exists (
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
    ) as monetary_receipt_exact,
    not exists (
      select 1
      from public.coordit_schema_change_records record
      where record.migration_version = '20260824'
        or record.migration_filename =
          '20260824_reconcile_profile_styling_schema.sql'
    ) as receipt_20260824_absent,
    exists (
      select 1
      from public.coordit_schema_change_records record
      where record.migration_version = '20260825'
        and record.migration_filename =
          current_setting('coordit.styling_schema_finalization_filename')
        and record.migration_sha256 =
          current_setting('coordit.styling_schema_finalization_sha256')
        and record.disposition = 'reconciled_observed_partial'
    ) as change_record_exact,
    (
      to_regclass('public.styling_looks') is not null
      and (
        select count(*) = 11
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'styling_looks'
      )
      and not exists (
        select 1
        from (values
          ('id', 'uuid', 'NO', 'gen_random_uuid()', 'NEVER'),
          ('user_id', 'uuid', 'NO', null, 'NEVER'),
          ('name', 'text', 'NO', null, 'NEVER'),
          ('name_ko', 'text', 'NO', null, 'NEVER'),
          ('mood', 'text', 'NO', '''''::text', 'NEVER'),
          ('palette', 'jsonb', 'NO', '''[]''::jsonb', 'NEVER'),
          ('ai_reasoning', 'text', 'NO', '''''::text', 'NEVER'),
          ('fit_score', 'numeric', 'YES', null, 'NEVER'),
          ('item_ids', 'jsonb', 'NO', '''[]''::jsonb', 'NEVER'),
          ('prompt', 'text', 'NO', '''''::text', 'NEVER'),
          ('created_at', 'timestamp with time zone', 'NO', 'now()', 'NEVER')
        ) expected(
          column_name,
          data_type,
          is_nullable,
          column_default,
          is_generated
        )
        left join information_schema.columns actual
          on actual.table_schema = 'public'
          and actual.table_name = 'styling_looks'
          and actual.column_name = expected.column_name
        where actual.column_name is null
          or actual.data_type is distinct from expected.data_type
          or actual.is_nullable is distinct from expected.is_nullable
          or actual.column_default is distinct from expected.column_default
          or actual.is_generated is distinct from expected.is_generated
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
    ) as styling_columns_exact,
    (
      select count(*) = 2
        and bool_or(
          constraint_row.conname = 'styling_looks_pkey'
          and pg_get_constraintdef(constraint_row.oid) = 'PRIMARY KEY (id)'
        )
        and bool_or(
          constraint_row.conname = 'styling_looks_user_id_fkey'
          and pg_get_constraintdef(constraint_row.oid) =
            'FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE'
        )
      from pg_constraint constraint_row
      where constraint_row.conrelid = 'public.styling_looks'::regclass
        and constraint_row.contype <> 'n'
    ) as styling_constraints_exact,
    (
      select count(*) = 2
        and bool_or(
          index_catalog.relname = 'styling_looks_user_id_idx'
          and access_method.amname = 'btree'
          and not index_row.indisunique
          and index_row.indisvalid
          and index_row.indisready
          and index_row.indexprs is null
          and index_row.indpred is null
          and pg_get_indexdef(index_catalog.oid) =
            'CREATE INDEX styling_looks_user_id_idx ON public.styling_looks USING btree (user_id)'
        )
      from pg_index index_row
      join pg_class index_catalog on index_catalog.oid = index_row.indexrelid
      join pg_am access_method on access_method.oid = index_catalog.relam
      where index_row.indrelid = 'public.styling_looks'::regclass
    ) as styling_index_exact,
    (
      select catalog.relkind = 'r'
        and catalog.relrowsecurity
        and not catalog.relforcerowsecurity
        and not exists (
          select 1
          from pg_policy policy_row
          where policy_row.polrelid = catalog.oid
        )
        and has_table_privilege('service_role', catalog.oid, 'select')
        and has_table_privilege('service_role', catalog.oid, 'insert')
        and has_table_privilege('service_role', catalog.oid, 'update')
        and has_table_privilege('service_role', catalog.oid, 'delete')
        and not has_table_privilege('service_role', catalog.oid, 'truncate')
        and not has_table_privilege('service_role', catalog.oid, 'references')
        and not has_table_privilege('service_role', catalog.oid, 'trigger')
        and not has_table_privilege('anon', catalog.oid, 'select')
        and not has_table_privilege('anon', catalog.oid, 'insert')
        and not has_table_privilege('anon', catalog.oid, 'update')
        and not has_table_privilege('anon', catalog.oid, 'delete')
        and not has_table_privilege('anon', catalog.oid, 'truncate')
        and not has_table_privilege('anon', catalog.oid, 'references')
        and not has_table_privilege('anon', catalog.oid, 'trigger')
        and not has_table_privilege('authenticated', catalog.oid, 'select')
        and not has_table_privilege('authenticated', catalog.oid, 'insert')
        and not has_table_privilege('authenticated', catalog.oid, 'update')
        and not has_table_privilege('authenticated', catalog.oid, 'delete')
        and not has_table_privilege('authenticated', catalog.oid, 'truncate')
        and not has_table_privilege('authenticated', catalog.oid, 'references')
        and not has_table_privilege('authenticated', catalog.oid, 'trigger')
      from pg_class catalog
      where catalog.oid = 'public.styling_looks'::regclass
    ) as styling_security_exact
` as const;
