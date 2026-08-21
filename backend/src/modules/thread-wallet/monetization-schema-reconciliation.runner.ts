import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { z } from "zod";
import type { Client } from "pg";

export const monetizationReconciliationApprovalToken =
  "coordit-monetization-schema-reconciliation-20260822" as const;
export const monetizationReconciliationFilename =
  "20260822_reconcile_monetization_release_schema.sql" as const;

const runnerOptionsSchema = z.object({
  approvalToken: z.literal(monetizationReconciliationApprovalToken),
  postflightMode: z.enum(["verify", "fail_after_migration"])
});
const approvalTokenSchema = z.literal(monetizationReconciliationApprovalToken);

const changeRecordSchema = z.object({
  migration_version: z.literal("20260822"),
  migration_filename: z.literal(monetizationReconciliationFilename),
  migration_sha256: z.string().regex(/^[0-9a-f]{64}$/),
  disposition: z.enum(["reconciled_observed_partial", "verified_exact_target"])
});

export type MonetizationReconciliationResult = z.infer<typeof changeRecordSchema>;

const fixedPostflightSql = `
  do $$
  begin
    if to_regclass('supabase_migrations.schema_migrations') is not null
      or to_regclass('public.coordit_schema_change_records') is null
      or to_regclass('public.coordit_monetization_schema_versions') is null
      or to_regclass('public.apple_iap_transactions') is null
      or to_regclass('public.apple_iap_notification_receipts') is null
      or position(
        'admob_transaction_attempt_conflict' in
        pg_get_functiondef('public.grant_admob_reward(uuid,text)'::regprocedure)
      ) = 0
      or not exists (
        select 1
        from public.coordit_schema_change_records record
        where record.migration_version = '20260822'
          and record.migration_filename = current_setting('coordit.reconciliation_filename')
          and record.migration_sha256 = current_setting('coordit.reconciliation_sha256')
          and record.disposition in ('reconciled_observed_partial', 'verified_exact_target')
      )
      or (
        select count(*)
        from public.coordit_monetization_schema_versions
        where (component, version) in (
          ('wallet', 1),
          ('admob_reward', 2),
          ('apple_iap', 2),
          ('apple_notifications', 2),
          ('release_reconciliation', 20260822)
        )
      ) <> 5
    then
      raise exception using
        errcode = '55000',
        message = 'monetization_reconciliation_postflight_failed';
    end if;
  end;
  $$;
`;

const forcedFailurePostflightSql = `
  do $$
  begin
    raise exception using
      errcode = 'P0001',
      message = 'monetization_reconciliation_test_postflight_failure';
  end;
  $$;
`;

const assertNever = (value: never): never => {
  throw new TypeError(`Unexpected reconciliation postflight mode: ${String(value)}`);
};

const runReconciliationTransaction = async (
  client: Client,
  rawOptions: z.input<typeof runnerOptionsSchema>
): Promise<MonetizationReconciliationResult> => {
  const options = runnerOptionsSchema.parse(rawOptions);
  const migrationPath = resolve(
    process.cwd(),
    "..",
    "supabase",
    "migrations",
    monetizationReconciliationFilename
  );
  const migrationSql = await readFile(migrationPath, "utf8");
  const migrationSha256 = createHash("sha256").update(migrationSql, "utf8").digest("hex");

  await client.query("begin");
  try {
    await client.query("set local lock_timeout='5s'; set local statement_timeout='30s'");
    await client.query(`
      select pg_advisory_xact_lock(
        hashtextextended('coordit:monetization-schema-reconciliation:20260822', 0)
      )
    `);
    await client.query(`
      select
        set_config('coordit.reconciliation_filename', $1::text, true),
        set_config('coordit.reconciliation_sha256', $2::text, true),
        set_config('coordit.reconciliation_lock_acquired', 'on', true)
    `, [monetizationReconciliationFilename, migrationSha256]);
    await client.query(migrationSql);

    switch (options.postflightMode) {
      case "verify":
        await client.query(fixedPostflightSql);
        break;
      case "fail_after_migration":
        await client.query(forcedFailurePostflightSql);
        break;
      default:
        assertNever(options.postflightMode);
    }

    const recordResult = await client.query(`
      select migration_version, migration_filename, migration_sha256, disposition
      from public.coordit_schema_change_records
      where migration_version = '20260822'
    `);
    const record = changeRecordSchema.parse(recordResult.rows[0]);
    await client.query("commit");
    return record;
  } catch (error) {
    await client.query("rollback");
    throw error;
  }
};

export const applyMonetizationSchemaReconciliation = async (
  client: Client,
  approvalToken: string
): Promise<MonetizationReconciliationResult> => {
  return runReconciliationTransaction(client, {
    approvalToken: approvalTokenSchema.parse(approvalToken),
    postflightMode: "verify"
  });
};

export const applyMonetizationSchemaReconciliationWithDisposableFailure = async (
  client: Client,
  approvalToken: string
): Promise<MonetizationReconciliationResult> => {
  return runReconciliationTransaction(client, {
    approvalToken: approvalTokenSchema.parse(approvalToken),
    postflightMode: "fail_after_migration"
  });
};
