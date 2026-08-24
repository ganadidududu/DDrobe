import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { z } from "zod";
import { postgresErrorSchema } from "../thread-wallet/apple-app-store-notification.db-assertions";
import { readProfileMutationSnapshot } from "./profile-styling-schema-reconciliation.db-assertions";
import { startDisposableProfileStylingDatabase } from "./profile-styling-schema-reconciliation.db-harness";
import {
  applyProfileStylingSchemaReconciliation,
  profileStylingReconciliationFilename
} from "./profile-styling-schema-reconciliation.runner";

const expectDatabaseError = async (
  operation: () => Promise<unknown>,
  expectedMessage: string
): Promise<void> => {
  await assert.rejects(operation, (error: unknown) => {
    const parsed = postgresErrorSchema.safeParse(error);
    return parsed.success && parsed.data.message === expectedMessage;
  });
};

const assertDriftRejected = async (
  mutationSql: string,
  expectedMessage = "profile_styling_catalog_drift"
): Promise<void> => {
  // Given: a production-like partial deliberately changed to an unsupported fingerprint.
  const database = await startDisposableProfileStylingDatabase();
  try {
    await database.client.query(mutationSql);
    const before = await readProfileMutationSnapshot(database.client);

    // When: the profile/styling runner evaluates the drifted catalog.
    await expectDatabaseError(
      () => database.applyProfileStylingReconciliation(),
      expectedMessage
    );

    // Then: no reconciliation-owned object changes before rejection.
    assert.deepEqual(await readProfileMutationSnapshot(database.client), before);
  } finally {
    await database.stop();
  }
};

const assertDirectExecutionRejected = async (): Promise<void> => {
  const database = await startDisposableProfileStylingDatabase();
  try {
    const migrationPath = resolve(
      process.cwd(),
      "..",
      "supabase",
      "migrations",
      profileStylingReconciliationFilename
    );
    const migrationSql = await readFile(migrationPath, "utf8");
    const before = await readProfileMutationSnapshot(database.client);
    await expectDatabaseError(
      () => database.client.query(migrationSql),
      "profile_styling_reconciliation_runner_context_required"
    );
    assert.deepEqual(await readProfileMutationSnapshot(database.client), before);
  } finally {
    await database.stop();
  }
};

const assertApprovalRejected = async (): Promise<void> => {
  const database = await startDisposableProfileStylingDatabase();
  try {
    const before = await readProfileMutationSnapshot(database.client);
    await assert.rejects(
      () => applyProfileStylingSchemaReconciliation(
        database.client,
        "approval-not-provided"
      ),
      (error: unknown) => error instanceof z.ZodError
    );
    assert.deepEqual(await readProfileMutationSnapshot(database.client), before);
  } finally {
    await database.stop();
  }
};

const assertConflictingReceiptRejected = async (): Promise<void> => {
  const database = await startDisposableProfileStylingDatabase();
  try {
    const migrationPath = resolve(
      process.cwd(),
      "..",
      "supabase",
      "migrations",
      profileStylingReconciliationFilename
    );
    const migrationSha = createHash("sha256")
      .update(await readFile(migrationPath, "utf8"), "utf8")
      .digest("hex");
    assert.notEqual(migrationSha, "0".repeat(64));
    await database.client.query(`
      insert into public.coordit_schema_change_records(
        migration_version, migration_filename, migration_sha256, disposition
      ) values (
        '20260824',
        '20260824_reconcile_profile_styling_schema.sql',
        repeat('0', 64),
        'reconciled_observed_partial'
      )
    `);
    const before = await readProfileMutationSnapshot(database.client);
    await expectDatabaseError(
      () => database.applyProfileStylingReconciliation(),
      "profile_styling_schema_change_record_conflict"
    );
    assert.deepEqual(await readProfileMutationSnapshot(database.client), before);
  } finally {
    await database.stop();
  }
};

const run = async (): Promise<void> => {
  await assertDirectExecutionRejected();
  await assertApprovalRejected();
  await assertDriftRejected(`
    create schema supabase_migrations;
    create table supabase_migrations.schema_migrations(version text primary key);
  `);
  await assertDriftRejected("alter table public.users add column birth_date date");
  await assertDriftRejected("alter table public.users add column birth_date text");
  await assertDriftRejected(`
    create table public.styling_looks (
      id uuid primary key,
      user_id uuid not null references public.users(id),
      name text not null,
      legacy_payload jsonb
    )
  `);
  {
    // Given: every compared target field matches, but name is generated instead of ordinary.
    const database = await startDisposableProfileStylingDatabase();
    try {
      await database.applyProfileStylingReconciliation();
      await database.client.query(`
        delete from public.coordit_schema_change_records
        where migration_version = '20260824';
        alter table public.styling_looks drop column name;
        alter table public.styling_looks add column name text
          generated always as ('generated'::text) stored not null;
      `);
      const generatedColumnResult = await database.client.query(`
        select data_type, is_nullable, column_default, is_generated
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'styling_looks'
          and column_name = 'name'
      `);
      assert.deepEqual(z.object({
        data_type: z.literal("text"),
        is_nullable: z.literal("NO"),
        column_default: z.null(),
        is_generated: z.literal("ALWAYS")
      }).parse(generatedColumnResult.rows[0]), {
        data_type: "text",
        is_nullable: "NO",
        column_default: null,
        is_generated: "ALWAYS"
      });
      const before = await readProfileMutationSnapshot(database.client);

      // When: the runner fingerprints the generated-column target.
      await expectDatabaseError(
        () => database.applyProfileStylingReconciliation(),
        "profile_styling_catalog_drift"
      );

      // Then: it rejects before recreating a verified-exact-target receipt.
      assert.deepEqual(await readProfileMutationSnapshot(database.client), before);
    } finally {
      await database.stop();
    }
  }
  await assertDriftRejected(
    "delete from public.coordit_schema_change_records where migration_version = '20260822'"
  );
  await assertConflictingReceiptRejected();
  process.stdout.write([
    "profile_styling_fingerprint_guard assertions=pass",
    "runner_context=required",
    "approval_token=required",
    "supabase_ledger=unexpected-drift",
    "paired_state=one-sided-rejected",
    "birth_date=wrong-type-rejected",
    "styling_looks=old-shape/wrong-column-rejected",
    "styling_looks=generated-name-rejected",
    "monetization_receipt=exact-required",
    "change_record=same-version-different-sha-rejected",
    "mutation=none-before-rejection",
    "identifiers=redacted",
    "cleanup=embedded-postgres-stopped-and-data-removed"
  ].join("\n") + "\n");
};

void run().catch((error: unknown) => {
  if (error instanceof Error) {
    process.stderr.write(`${error.name}: ${error.message}\n`);
  } else {
    process.stderr.write("Unknown profile/styling fingerprint test failure\n");
  }
  process.exit(1);
});
