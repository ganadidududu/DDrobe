import { z } from "zod";
import type { Client } from "pg";
import {
  readStylingColumns,
  readStylingConstraints,
  readStylingIndexes,
  readStylingSecurity,
  readUserColumnNames
} from "./profile-styling-schema-reconciliation.db-assertions";

const uuidSchema = z.string().uuid();

const capabilitiesSchema = z.object({
  birth_date_exact: z.boolean(),
  receipt_20260824: z.boolean(),
  receipt_20260825: z.boolean(),
  styling_looks: z.boolean()
});

const changeRecordSchema = z.object({
  migration_version: z.literal("20260825"),
  migration_filename: z.literal("20260825_finalize_styling_schema.sql"),
  migration_sha256: z.string().regex(/^[0-9a-f]{64}$/),
  disposition: z.literal("reconciled_observed_partial"),
  applied_at: z.date()
});

const birthDateDefinitionSchema = z.array(z.object({
  data_type: z.string(),
  is_generated: z.string(),
  is_nullable: z.string(),
  column_default: z.string().nullable()
}));

const sentinelSnapshotSchema = z.object({
  user: z.object({
    id: uuidSchema,
    birth_date: z.string()
  }),
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

export const readStylingFinalizationCapabilities = async (
  client: Client
): Promise<z.infer<typeof capabilitiesSchema>> => {
  const result = await client.query(`
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
      to_regclass('public.styling_looks') is not null as styling_looks,
      exists (
        select 1 from public.coordit_schema_change_records
        where migration_version = '20260824'
          or migration_filename = '20260824_reconcile_profile_styling_schema.sql'
      ) as receipt_20260824,
      exists (
        select 1 from public.coordit_schema_change_records
        where migration_version = '20260825'
          or migration_filename = '20260825_finalize_styling_schema.sql'
      ) as receipt_20260825
  `);
  return capabilitiesSchema.parse(result.rows[0]);
};

export const readStylingFinalizationChangeRecord = async (
  client: Client
): Promise<z.infer<typeof changeRecordSchema>> => {
  const result = await client.query(`
    select migration_version, migration_filename, migration_sha256, disposition, applied_at
    from public.coordit_schema_change_records
    where migration_version = '20260825'
  `);
  return changeRecordSchema.parse(result.rows[0]);
};

export const readBirthDateDefinition = async (
  client: Client
): Promise<z.infer<typeof birthDateDefinitionSchema>> => {
  const result = await client.query(`
    select data_type, is_nullable, column_default, is_generated
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'birth_date'
  `);
  return birthDateDefinitionSchema.parse(result.rows);
};

export const readStylingFinalizationMutationSnapshot = async (
  client: Client
): Promise<{
  readonly birthDateDefinition: z.infer<typeof birthDateDefinitionSchema>;
  readonly receiptCount: number;
  readonly publicTables: readonly string[];
  readonly stylingColumns: Awaited<ReturnType<typeof readStylingColumns>>;
  readonly stylingConstraints: Awaited<ReturnType<typeof readStylingConstraints>>;
  readonly stylingIndexes: Awaited<ReturnType<typeof readStylingIndexes>>;
  readonly stylingSecurity: Awaited<ReturnType<typeof readStylingSecurity>> | null;
  readonly userColumns: readonly string[];
}> => {
  const tableResult = await client.query(`
    select tablename
    from pg_tables
    where schemaname = 'public'
    order by tablename
  `);
  const recordResult = await client.query(`
    select count(*)
    from public.coordit_schema_change_records
    where migration_version in ('20260824', '20260825')
      or migration_filename in (
        '20260824_reconcile_profile_styling_schema.sql',
        '20260825_finalize_styling_schema.sql'
      )
  `);
  const stylingResult = await client.query(
    "select to_regclass('public.styling_looks') is not null as exists"
  );
  const stylingExists = z.object({ exists: z.boolean() }).parse(stylingResult.rows[0]).exists;
  return {
    birthDateDefinition: await readBirthDateDefinition(client),
    receiptCount: z.coerce.number().int().nonnegative().parse(recordResult.rows[0]?.count),
    publicTables: z.array(z.object({ tablename: z.string() }))
      .parse(tableResult.rows)
      .map((row) => row.tablename),
    stylingColumns: await readStylingColumns(client),
    stylingConstraints: stylingExists ? await readStylingConstraints(client) : [],
    stylingIndexes: stylingExists ? await readStylingIndexes(client) : [],
    stylingSecurity: stylingExists ? await readStylingSecurity(client) : null,
    userColumns: await readUserColumnNames(client)
  };
};

export const readStylingFinalizationSentinelSnapshot = async (
  client: Client,
  userId: string,
  ledgerId: string
): Promise<z.infer<typeof sentinelSnapshotSchema>> => {
  const userResult = await client.query(`
    select id, birth_date::text as birth_date
    from public.users
    where id = $1::uuid
  `, [userId]);
  const balanceResult = await client.query(`
    select user_id, available_threads, updated_at
    from public.thread_balances
    where user_id = $1::uuid
  `, [userId]);
  const ledgerResult = await client.query(`
    select id, user_id, idempotency_key, fit_analysis_result_id,
      apple_iap_transaction_id, amount, reason, created_at
    from public.thread_ledger_entries
    where id = $1::uuid
  `, [ledgerId]);
  return sentinelSnapshotSchema.parse({
    user: userResult.rows[0],
    balance: balanceResult.rows[0],
    ledger: ledgerResult.rows[0]
  });
};
