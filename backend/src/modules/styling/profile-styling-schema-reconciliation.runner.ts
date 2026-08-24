import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import type { Client } from "pg";
import { z } from "zod";
import {
  profileStylingPostflightRowSchema,
  profileStylingPostflightSql
} from "./profile-styling-schema-reconciliation.postflight";

export const profileStylingReconciliationApprovalToken =
  "coordit-profile-styling-schema-reconciliation-20260824" as const;
export const profileStylingReconciliationFilename =
  "20260824_reconcile_profile_styling_schema.sql" as const;

const runnerOptionsSchema = z.object({
  approvalToken: z.literal(profileStylingReconciliationApprovalToken),
  postflightMode: z.enum(["verify", "fail_after_migration"])
});
const approvalTokenSchema = z.literal(profileStylingReconciliationApprovalToken);

const changeRecordSchema = z.object({
  migration_version: z.literal("20260824"),
  migration_filename: z.literal(profileStylingReconciliationFilename),
  migration_sha256: z.string().regex(/^[0-9a-f]{64}$/),
  disposition: z.enum(["reconciled_observed_partial", "verified_exact_target"])
});

export type ProfileStylingReconciliationResult = z.infer<typeof changeRecordSchema>;

const forcedFailurePostflightSql = `
  do $$
  begin
    raise exception using
      errcode = 'P0001',
      message = 'profile_styling_reconciliation_test_postflight_failure';
  end;
  $$;
`;

const assertNever = (value: never): never => {
  throw new TypeError(`Unexpected profile/styling postflight mode: ${String(value)}`);
};

const runReconciliationTransaction = async (
  client: Client,
  rawOptions: z.input<typeof runnerOptionsSchema>
): Promise<ProfileStylingReconciliationResult> => {
  const options = runnerOptionsSchema.parse(rawOptions);
  const migrationPath = resolve(
    process.cwd(),
    "..",
    "supabase",
    "migrations",
    profileStylingReconciliationFilename
  );
  const migrationSql = await readFile(migrationPath, "utf8");
  const migrationSha256 = createHash("sha256")
    .update(migrationSql, "utf8")
    .digest("hex");

  await client.query("begin");
  try {
    await client.query("set local lock_timeout='5s'; set local statement_timeout='30s'");
    await client.query(`
      select pg_advisory_xact_lock(
        hashtextextended('coordit:profile-styling-schema-reconciliation:20260824', 0)
      )
    `);
    await client.query(`
      select
        set_config(
          'coordit.profile_styling_reconciliation_filename',
          $1::text,
          true
        ),
        set_config(
          'coordit.profile_styling_reconciliation_sha256',
          $2::text,
          true
        ),
        set_config(
          'coordit.profile_styling_reconciliation_lock_acquired',
          'on',
          true
        )
    `, [profileStylingReconciliationFilename, migrationSha256]);
    await client.query(migrationSql);

    switch (options.postflightMode) {
      case "verify": {
        const postflightResult = await client.query(profileStylingPostflightSql);
        profileStylingPostflightRowSchema.parse(postflightResult.rows[0]);
        break;
      }
      case "fail_after_migration":
        await client.query(forcedFailurePostflightSql);
        break;
      default:
        assertNever(options.postflightMode);
    }

    const recordResult = await client.query(`
      select migration_version, migration_filename, migration_sha256, disposition
      from public.coordit_schema_change_records
      where migration_version = '20260824'
    `);
    const record = changeRecordSchema.parse(recordResult.rows[0]);
    await client.query("commit");
    return record;
  } catch (error: unknown) {
    await client.query("rollback");
    throw error;
  }
};

export const applyProfileStylingSchemaReconciliation = async (
  client: Client,
  approvalToken: string
): Promise<ProfileStylingReconciliationResult> => {
  return runReconciliationTransaction(client, {
    approvalToken: approvalTokenSchema.parse(approvalToken),
    postflightMode: "verify"
  });
};

export const applyProfileStylingSchemaReconciliationWithDisposableFailure = async (
  client: Client,
  approvalToken: string
): Promise<ProfileStylingReconciliationResult> => {
  return runReconciliationTransaction(client, {
    approvalToken: approvalTokenSchema.parse(approvalToken),
    postflightMode: "fail_after_migration"
  });
};
