import { z } from "zod";
import type { Client } from "pg";

const uuidSchema = z.string().uuid();

const capabilitiesSchema = z.object({
  birth_date: z.boolean(),
  change_record: z.boolean(),
  styling_looks: z.boolean()
});

const changeRecordSchema = z.object({
  migration_version: z.literal("20260824"),
  migration_filename: z.literal("20260824_reconcile_profile_styling_schema.sql"),
  migration_sha256: z.string().regex(/^[0-9a-f]{64}$/),
  disposition: z.enum(["reconciled_observed_partial", "verified_exact_target"]),
  applied_at: z.date()
});

const columnSchema = z.object({
  column_name: z.string(),
  data_type: z.string(),
  is_nullable: z.enum(["YES", "NO"]),
  column_default: z.string().nullable(),
  numeric_precision: z.number().nullable(),
  numeric_scale: z.number().nullable()
});

const namedDefinitionSchema = z.object({
  name: z.string(),
  definition: z.string()
});

const securitySchema = z.object({
  rls_enabled: z.boolean(),
  force_rls: z.boolean(),
  policy_count: z.coerce.number().int().nonnegative(),
  service_select: z.boolean(),
  service_insert: z.boolean(),
  service_update: z.boolean(),
  service_delete: z.boolean(),
  service_extra: z.boolean(),
  anon_access: z.boolean(),
  authenticated_access: z.boolean()
});

const sentinelSnapshotSchema = z.object({
  user: z.object({ id: uuidSchema }),
  balance: z.object({
    user_id: uuidSchema,
    available_threads: z.number().int().nonnegative(),
    updated_at: z.date()
  }),
  ledger: z.object({
    id: uuidSchema,
    user_id: uuidSchema,
    idempotency_key: uuidSchema,
    fit_analysis_result_id: uuidSchema.nullable(),
    apple_iap_transaction_id: uuidSchema.nullable(),
    amount: z.number().int(),
    reason: z.string(),
    created_at: z.date()
  })
});

export const readProfileStylingCapabilities = async (
  client: Client
): Promise<z.infer<typeof capabilitiesSchema>> => {
  const result = await client.query(`
    select
      exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'users'
          and column_name = 'birth_date'
      ) as birth_date,
      to_regclass('public.styling_looks') is not null as styling_looks,
      exists (
        select 1 from public.coordit_schema_change_records
        where migration_version = '20260824'
      ) as change_record
  `);
  return capabilitiesSchema.parse(result.rows[0]);
};

export const readProfileStylingChangeRecord = async (
  client: Client
): Promise<z.infer<typeof changeRecordSchema>> => {
  const result = await client.query(`
    select migration_version, migration_filename, migration_sha256, disposition, applied_at
    from public.coordit_schema_change_records
    where migration_version = '20260824'
  `);
  return changeRecordSchema.parse(result.rows[0]);
};

export const readUserColumnNames = async (client: Client): Promise<readonly string[]> => {
  const result = await client.query(`
    select column_name
    from information_schema.columns
    where table_schema = 'public' and table_name = 'users'
    order by ordinal_position
  `);
  return z.array(z.object({ column_name: z.string() }))
    .parse(result.rows)
    .map((row) => row.column_name);
};

export const readStylingColumns = async (
  client: Client
): Promise<readonly z.infer<typeof columnSchema>[]> => {
  const result = await client.query(`
    select column_name, data_type, is_nullable, column_default,
      numeric_precision, numeric_scale
    from information_schema.columns
    where table_schema = 'public' and table_name = 'styling_looks'
    order by ordinal_position
  `);
  return z.array(columnSchema).parse(result.rows);
};

export const readStylingConstraints = async (
  client: Client
): Promise<readonly z.infer<typeof namedDefinitionSchema>[]> => {
  const result = await client.query(`
    select conname as name, pg_get_constraintdef(oid) as definition
    from pg_constraint
    where conrelid = 'public.styling_looks'::regclass and contype <> 'n'
    order by conname
  `);
  return z.array(namedDefinitionSchema).parse(result.rows);
};

export const readStylingIndexes = async (
  client: Client
): Promise<readonly z.infer<typeof namedDefinitionSchema>[]> => {
  const result = await client.query(`
    select indexname as name, indexdef as definition
    from pg_indexes
    where schemaname = 'public' and tablename = 'styling_looks'
    order by indexname
  `);
  return z.array(namedDefinitionSchema).parse(result.rows);
};

export const readStylingSecurity = async (
  client: Client
): Promise<z.infer<typeof securitySchema>> => {
  const result = await client.query(`
    select
      catalog.relrowsecurity as rls_enabled,
      catalog.relforcerowsecurity as force_rls,
      (select count(*) from pg_policy where polrelid = catalog.oid) as policy_count,
      has_table_privilege('service_role', catalog.oid, 'select') as service_select,
      has_table_privilege('service_role', catalog.oid, 'insert') as service_insert,
      has_table_privilege('service_role', catalog.oid, 'update') as service_update,
      has_table_privilege('service_role', catalog.oid, 'delete') as service_delete,
      has_table_privilege('service_role', catalog.oid, 'truncate')
        or has_table_privilege('service_role', catalog.oid, 'references')
        or has_table_privilege('service_role', catalog.oid, 'trigger') as service_extra,
      has_table_privilege('anon', catalog.oid, 'select')
        or has_table_privilege('anon', catalog.oid, 'insert')
        or has_table_privilege('anon', catalog.oid, 'update')
        or has_table_privilege('anon', catalog.oid, 'delete')
        or has_table_privilege('anon', catalog.oid, 'truncate')
        or has_table_privilege('anon', catalog.oid, 'references')
        or has_table_privilege('anon', catalog.oid, 'trigger') as anon_access,
      has_table_privilege('authenticated', catalog.oid, 'select')
        or has_table_privilege('authenticated', catalog.oid, 'insert')
        or has_table_privilege('authenticated', catalog.oid, 'update')
        or has_table_privilege('authenticated', catalog.oid, 'delete')
        or has_table_privilege('authenticated', catalog.oid, 'truncate')
        or has_table_privilege('authenticated', catalog.oid, 'references')
        or has_table_privilege('authenticated', catalog.oid, 'trigger')
        as authenticated_access
    from pg_class catalog
    where catalog.oid = 'public.styling_looks'::regclass
  `);
  return securitySchema.parse(result.rows[0]);
};

export const readProfileMutationSnapshot = async (client: Client): Promise<{
  readonly profileRecordCount: number;
  readonly publicTables: readonly string[];
  readonly stylingColumns: readonly z.infer<typeof columnSchema>[];
  readonly userColumns: readonly string[];
}> => {
  const tableResult = await client.query(`
    select tablename
    from pg_tables where schemaname = 'public'
    order by tablename
  `);
  const recordResult = await client.query(`
    select count(*)
    from public.coordit_schema_change_records
    where migration_version = '20260824'
      or migration_filename = '20260824_reconcile_profile_styling_schema.sql'
  `);
  return {
    profileRecordCount: z.coerce.number().int().nonnegative()
      .parse(recordResult.rows[0]?.count),
    publicTables: z.array(z.object({ tablename: z.string() }))
      .parse(tableResult.rows)
      .map((row) => row.tablename),
    stylingColumns: await readStylingColumns(client),
    userColumns: await readUserColumnNames(client)
  };
};

export const readSentinelSnapshot = async (
  client: Client,
  userId: string,
  ledgerId: string
): Promise<z.infer<typeof sentinelSnapshotSchema>> => {
  const userResult = await client.query(
    "select id from public.users where id = $1::uuid",
    [userId]
  );
  const balanceResult = await client.query(`
    select user_id, available_threads, updated_at
    from public.thread_balances where user_id = $1::uuid
  `, [userId]);
  const ledgerResult = await client.query(`
    select id, user_id, idempotency_key, fit_analysis_result_id,
      apple_iap_transaction_id, amount, reason, created_at
    from public.thread_ledger_entries where id = $1::uuid
  `, [ledgerId]);
  return sentinelSnapshotSchema.parse({
    user: userResult.rows[0],
    balance: balanceResult.rows[0],
    ledger: ledgerResult.rows[0]
  });
};
