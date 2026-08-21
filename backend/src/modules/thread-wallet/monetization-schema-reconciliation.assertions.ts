import assert from "node:assert/strict";
import { z } from "zod";
import type { Client } from "pg";

export const monetizationSchemaMarkers = [
  { component: "wallet", version: 1 },
  { component: "admob_reward", version: 2 },
  { component: "apple_iap", version: 2 },
  { component: "apple_notifications", version: 2 },
  { component: "release_reconciliation", version: 20260822 }
] as const;

const capabilitySchema = z.object({
  apple_transactions: z.boolean(),
  apple_notifications: z.boolean(),
  marker_table: z.boolean(),
  change_record_table: z.boolean(),
  supabase_migration_ledger: z.boolean(),
  admob_hardened: z.boolean(),
  birth_date: z.boolean(),
  styling_looks: z.boolean()
});

const walletSnapshotSchema = z.object({
  balance: z.number().int().nonnegative(),
  ledger_count: z.coerce.number().int().nonnegative(),
  attempt_count: z.coerce.number().int().nonnegative()
});

const markerSchema = z.object({
  component: z.string().min(1),
  version: z.number().int().positive(),
  installed_at: z.date()
});

const changeRecordSchema = z.object({
  migration_version: z.literal("20260822"),
  migration_filename: z.literal("20260822_reconcile_monetization_release_schema.sql"),
  migration_sha256: z.string().regex(/^[0-9a-f]{64}$/),
  disposition: z.enum(["reconciled_observed_partial", "verified_exact_target"]),
  applied_at: z.date()
});

const securityRowSchema = z.object({
  rls_count: z.coerce.number().int(),
  service_execute: z.boolean(),
  anon_execute: z.boolean(),
  authenticated_execute: z.boolean(),
  anon_table_read: z.boolean(),
  authenticated_table_read: z.boolean(),
  service_record_read: z.boolean(),
  service_record_write: z.boolean()
});

export const readCapabilities = async (
  client: Client
): Promise<z.infer<typeof capabilitySchema>> => {
  const result = await client.query(`
    select
      to_regclass('public.apple_iap_transactions') is not null as apple_transactions,
      to_regclass('public.apple_iap_notification_receipts') is not null as apple_notifications,
      to_regclass('public.coordit_monetization_schema_versions') is not null as marker_table,
      to_regclass('public.coordit_schema_change_records') is not null as change_record_table,
      to_regclass('supabase_migrations.schema_migrations') is not null as supabase_migration_ledger,
      position(
        'admob_transaction_attempt_conflict' in
        pg_get_functiondef('public.grant_admob_reward(uuid,text)'::regprocedure)
      ) > 0 as admob_hardened,
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'users' and column_name = 'birth_date'
      ) as birth_date,
      to_regclass('public.styling_looks') is not null as styling_looks
  `);
  return capabilitySchema.parse(result.rows[0]);
};

export const readPublicTableNames = async (client: Client): Promise<readonly string[]> => {
  const result = await client.query(`
    select tablename
    from pg_tables
    where schemaname = 'public'
    order by tablename
  `);
  return z.array(z.object({ tablename: z.string() })).parse(result.rows).map((row) => row.tablename);
};

export const readWalletSnapshot = async (
  client: Client,
  userId: string
): Promise<z.infer<typeof walletSnapshotSchema>> => {
  const result = await client.query(`
    select
      balance.available_threads as balance,
      (select count(*) from public.thread_ledger_entries entry where entry.user_id = $1::uuid) as ledger_count,
      (select count(*) from public.admob_reward_attempts attempt where attempt.user_id = $1::uuid) as attempt_count
    from public.thread_balances balance
    where balance.user_id = $1::uuid
  `, [userId]);
  return walletSnapshotSchema.parse(result.rows[0]);
};

export const readSchemaMarkers = async (
  client: Client
): Promise<readonly z.infer<typeof markerSchema>[]> => {
  const result = await client.query(`
    select component, version, installed_at
    from public.coordit_monetization_schema_versions
    order by component
  `);
  return z.array(markerSchema).parse(result.rows);
};

export const readChangeRecord = async (
  client: Client
): Promise<z.infer<typeof changeRecordSchema>> => {
  const result = await client.query(`
    select migration_version, migration_filename, migration_sha256, disposition, applied_at
    from public.coordit_schema_change_records
    where migration_version = '20260822'
  `);
  return changeRecordSchema.parse(result.rows[0]);
};

export const assertReconciledSecurity = async (client: Client): Promise<void> => {
  const result = await client.query(`
    with monetary_rpc(signature) as (values
      ('public.get_thread_balance(uuid)'),
      ('public.consume_fit_analysis_thread(uuid,uuid,uuid)'),
      ('public.create_fit_analysis_result_and_consume_thread(uuid,uuid,jsonb)'),
      ('public.consume_fit_report_thread(uuid,uuid,uuid)'),
      ('public.create_admob_reward_attempt(uuid)'),
      ('public.grant_admob_reward(uuid,text)'),
      ('public.grant_apple_iap_threads(uuid,text,text,text,uuid,timestamptz,text,integer)'),
      ('public.record_apple_iap_notification(uuid,text,text,text)'),
      ('public.reconcile_apple_iap_notification(uuid,text,text,text,uuid,text,text,text,uuid,timestamptz,text,integer)')
    )
    select
      (
        select count(*) filter (where c.relrowsecurity)
        from pg_class c
        where c.oid in (
          'public.thread_balances'::regclass,
          'public.thread_ledger_entries'::regclass,
          'public.admob_reward_attempts'::regclass,
          'public.admob_reward_transactions'::regclass,
          'public.apple_iap_transactions'::regclass,
          'public.apple_iap_notification_receipts'::regclass,
          'public.coordit_monetization_schema_versions'::regclass,
          'public.coordit_schema_change_records'::regclass
        )
      ) as rls_count,
      (select bool_and(has_function_privilege('service_role', signature, 'execute')) from monetary_rpc)
        as service_execute,
      (select bool_or(has_function_privilege('anon', signature, 'execute')) from monetary_rpc)
        as anon_execute,
      (select bool_or(has_function_privilege('authenticated', signature, 'execute')) from monetary_rpc)
        as authenticated_execute,
      has_table_privilege('anon', 'public.apple_iap_transactions', 'select')
        or has_table_privilege('anon', 'public.apple_iap_notification_receipts', 'select')
        or has_table_privilege('anon', 'public.coordit_monetization_schema_versions', 'select')
        or has_table_privilege('anon', 'public.coordit_schema_change_records', 'select')
        as anon_table_read,
      has_table_privilege('authenticated', 'public.apple_iap_transactions', 'select')
        or has_table_privilege('authenticated', 'public.apple_iap_notification_receipts', 'select')
        or has_table_privilege('authenticated', 'public.coordit_monetization_schema_versions', 'select')
        or has_table_privilege('authenticated', 'public.coordit_schema_change_records', 'select')
        as authenticated_table_read,
      has_table_privilege('service_role', 'public.coordit_schema_change_records', 'select')
        as service_record_read,
      has_table_privilege('service_role', 'public.coordit_schema_change_records', 'insert')
        or has_table_privilege('service_role', 'public.coordit_schema_change_records', 'update')
        or has_table_privilege('service_role', 'public.coordit_schema_change_records', 'delete')
        or has_table_privilege('service_role', 'public.coordit_schema_change_records', 'truncate')
        or has_table_privilege('service_role', 'public.coordit_schema_change_records', 'references')
        or has_table_privilege('service_role', 'public.coordit_schema_change_records', 'trigger')
        as service_record_write
  `);
  assert.deepEqual(securityRowSchema.parse(result.rows[0]), {
    rls_count: 8,
    service_execute: true,
    anon_execute: false,
    authenticated_execute: false,
    anon_table_read: false,
    authenticated_table_read: false,
    service_record_read: true,
    service_record_write: false
  });
};
