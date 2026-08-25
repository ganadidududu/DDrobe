import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import type { Client } from "pg";
import { z } from "zod";
import {
  stylingSchemaFinalizationPostflightRowSchema,
  stylingSchemaFinalizationPostflightSql
} from "./styling-schema-finalization.postflight";

export const stylingSchemaFinalizationApprovalToken =
  "coordit-styling-schema-finalization-20260825" as const;
export const stylingSchemaFinalizationFilename =
  "20260825_finalize_styling_schema.sql" as const;

const runnerOptionsSchema = z.object({
  approvalToken: z.literal(stylingSchemaFinalizationApprovalToken),
  postflightMode: z.enum(["verify", "fail_after_migration"])
});
const approvalTokenSchema = z.literal(stylingSchemaFinalizationApprovalToken);

const changeRecordSchema = z.object({
  migration_version: z.literal("20260825"),
  migration_filename: z.literal(stylingSchemaFinalizationFilename),
  migration_sha256: z.string().regex(/^[0-9a-f]{64}$/),
  disposition: z.literal("reconciled_observed_partial")
});

export type StylingSchemaFinalizationResult = z.infer<typeof changeRecordSchema>;

const forcedFailurePostflightSql = `
  do $$
  begin
    raise exception using
      errcode = 'P0001',
      message = 'styling_schema_finalization_test_postflight_failure';
  end;
  $$;
`;

const assertNever = (value: never): never => {
  throw new TypeError(`Unexpected styling finalization postflight mode: ${String(value)}`);
};

const runFinalizationTransaction = async (
  client: Client,
  rawOptions: z.input<typeof runnerOptionsSchema>
): Promise<StylingSchemaFinalizationResult> => {
  const options = runnerOptionsSchema.parse(rawOptions);
  const migrationPath = resolve(
    process.cwd(),
    "..",
    "supabase",
    "migrations",
    stylingSchemaFinalizationFilename
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
        hashtextextended('coordit:styling-schema-finalization:20260825', 0)
      )
    `);
    await client.query(`
      select
        set_config(
          'coordit.styling_schema_finalization_filename',
          $1::text,
          true
        ),
        set_config(
          'coordit.styling_schema_finalization_sha256',
          $2::text,
          true
        ),
        set_config(
          'coordit.styling_schema_finalization_lock_acquired',
          'on',
          true
        )
    `, [stylingSchemaFinalizationFilename, migrationSha256]);
    await client.query(migrationSql);

    switch (options.postflightMode) {
      case "verify": {
        const postflightResult = await client.query(stylingSchemaFinalizationPostflightSql);
        stylingSchemaFinalizationPostflightRowSchema.parse(postflightResult.rows[0]);
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
      where migration_version = '20260825'
    `);
    const record = changeRecordSchema.parse(recordResult.rows[0]);
    await client.query("commit");
    return record;
  } catch (error: unknown) {
    await client.query("rollback");
    throw error;
  }
};

export const applyStylingSchemaFinalization = async (
  client: Client,
  approvalToken: string
): Promise<StylingSchemaFinalizationResult> => {
  return runFinalizationTransaction(client, {
    approvalToken: approvalTokenSchema.parse(approvalToken),
    postflightMode: "verify"
  });
};

export const applyStylingSchemaFinalizationWithDisposableFailure = async (
  client: Client,
  approvalToken: string
): Promise<StylingSchemaFinalizationResult> => {
  return runFinalizationTransaction(client, {
    approvalToken: approvalTokenSchema.parse(approvalToken),
    postflightMode: "fail_after_migration"
  });
};
