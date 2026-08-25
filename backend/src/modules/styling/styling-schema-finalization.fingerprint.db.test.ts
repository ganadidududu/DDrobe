import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { z } from "zod";
import { postgresErrorSchema } from "../thread-wallet/apple-app-store-notification.db-assertions";
import {
  readStylingFinalizationMutationSnapshot
} from "./styling-schema-finalization.db-assertions";
import { startDisposableStylingFinalizationDatabase } from "./styling-schema-finalization.db-harness";
import {
  applyStylingSchemaFinalization,
  stylingSchemaFinalizationFilename
} from "./styling-schema-finalization.runner";

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
  setupSql: string,
  expectedMessage = "styling_schema_finalization_catalog_drift"
): Promise<void> => {
  const database = await startDisposableStylingFinalizationDatabase();
  try {
    await database.client.query(setupSql);
    const before = await readStylingFinalizationMutationSnapshot(database.client);
    await expectDatabaseError(
      () => database.applyStylingFinalization(),
      expectedMessage
    );
    assert.deepEqual(await readStylingFinalizationMutationSnapshot(database.client), before);
  } finally {
    await database.stop();
  }
};

const assertExactTargetDriftRejected = async (setupSql: string): Promise<void> => {
  const database = await startDisposableStylingFinalizationDatabase();
  try {
    await database.applyStylingFinalization();
    await database.client.query(setupSql);
    const before = await readStylingFinalizationMutationSnapshot(database.client);
    await expectDatabaseError(
      () => database.applyStylingFinalization(),
      "styling_schema_finalization_catalog_drift"
    );
    assert.deepEqual(await readStylingFinalizationMutationSnapshot(database.client), before);
  } finally {
    await database.stop();
  }
};

const assertDirectExecutionRejected = async (): Promise<void> => {
  const database = await startDisposableStylingFinalizationDatabase();
  try {
    const migrationPath = resolve(
      process.cwd(),
      "..",
      "supabase",
      "migrations",
      stylingSchemaFinalizationFilename
    );
    const migrationSql = await readFile(migrationPath, "utf8");
    const before = await readStylingFinalizationMutationSnapshot(database.client);
    await expectDatabaseError(
      () => database.client.query(migrationSql),
      "styling_schema_finalization_runner_context_required"
    );
    assert.deepEqual(await readStylingFinalizationMutationSnapshot(database.client), before);
  } finally {
    await database.stop();
  }
};

const assertApprovalRejected = async (): Promise<void> => {
  const database = await startDisposableStylingFinalizationDatabase();
  try {
    const before = await readStylingFinalizationMutationSnapshot(database.client);
    await assert.rejects(
      () => applyStylingSchemaFinalization(database.client, "approval-not-provided"),
      (error: unknown) => error instanceof z.ZodError
    );
    assert.deepEqual(await readStylingFinalizationMutationSnapshot(database.client), before);
  } finally {
    await database.stop();
  }
};

const assertGeneratedNameRejected = async (): Promise<void> => {
  const database = await startDisposableStylingFinalizationDatabase();
  try {
    await database.applyStylingFinalization();
    await database.client.query(`
      alter table public.styling_looks drop column name;
      alter table public.styling_looks add column name text
        generated always as ('generated'::text) stored not null;
    `);
    const generatedResult = await database.client.query(`
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
    }).parse(generatedResult.rows[0]), {
      data_type: "text",
      is_nullable: "NO",
      column_default: null,
      is_generated: "ALWAYS"
    });
    const before = await readStylingFinalizationMutationSnapshot(database.client);
    await expectDatabaseError(
      () => database.applyStylingFinalization(),
      "styling_schema_finalization_catalog_drift"
    );
    assert.deepEqual(await readStylingFinalizationMutationSnapshot(database.client), before);
  } finally {
    await database.stop();
  }
};

const assertUnloggedExactTargetRejected = async (): Promise<void> => {
  const database = await startDisposableStylingFinalizationDatabase();
  try {
    await database.applyStylingFinalization();
    await database.client.query("alter table public.styling_looks set unlogged");
    const before = await readStylingFinalizationMutationSnapshot(database.client);
    assert.equal(before.stylingPersistence, "u");
    await expectDatabaseError(
      () => database.applyStylingFinalization(),
      "styling_schema_finalization_catalog_drift"
    );
    assert.deepEqual(await readStylingFinalizationMutationSnapshot(database.client), before);
  } finally {
    await database.stop();
  }
};

const readExpectedSha = async (): Promise<string> => {
  const migrationPath = resolve(
    process.cwd(),
    "..",
    "supabase",
    "migrations",
    stylingSchemaFinalizationFilename
  );
  return createHash("sha256")
    .update(await readFile(migrationPath, "utf8"), "utf8")
    .digest("hex");
};

const run = async (): Promise<void> => {
  await assertDirectExecutionRejected();
  await assertApprovalRejected();

  const driftScenarios = [
    `create schema supabase_migrations;
     create table supabase_migrations.schema_migrations(version text primary key);`,
    "alter table public.users drop column birth_date",
    "alter table public.users alter column birth_date type text using birth_date::text",
    "alter table public.users alter column birth_date set not null",
    "alter table public.users alter column birth_date set default current_date",
    `alter table public.users drop column birth_date;
     alter table public.users add column birth_date date
       generated always as ('2000-01-01'::date) stored;`,
    `create table public.styling_looks (
       id uuid primary key,
       user_id uuid not null references public.users(id),
       name text not null,
       legacy_payload jsonb
     );`,
    `insert into public.coordit_schema_change_records(
       migration_version, migration_filename, migration_sha256, disposition
     ) values (
       '20260824', '20260824_reconcile_profile_styling_schema.sql',
       '3d2bd3c10d6688d5f5fa6d1ccc010aa3a932478b16536bc68a41d4c50b116c17',
       'reconciled_observed_partial'
     );`,
    "delete from public.coordit_schema_change_records where migration_version = '20260822'",
    `update public.coordit_schema_change_records
     set migration_sha256 = repeat('0', 64)
     where migration_version = '20260822'`
  ] as const;
  for (const setupSql of driftScenarios) {
    await assertDriftRejected(setupSql);
  }

  await assertDriftRejected(`
    insert into public.coordit_schema_change_records(
      migration_version, migration_filename, migration_sha256, disposition
    ) values (
      '20260825', '20260825_finalize_styling_schema.sql', repeat('0', 64),
      'reconciled_observed_partial'
    )
  `, "styling_schema_finalization_change_record_conflict");

  await assertExactTargetDriftRejected(`
    delete from public.coordit_schema_change_records
    where migration_version = '20260825'
  `);
  await assertExactTargetDriftRejected(
    "alter table public.styling_looks disable row level security"
  );
  await assertExactTargetDriftRejected(
    "grant select on table public.styling_looks to anon"
  );
  await assertExactTargetDriftRejected(`
    drop index public.styling_looks_user_id_idx;
    create index styling_looks_user_id_idx
      on public.styling_looks using hash(user_id)
  `);
  await assertExactTargetDriftRejected(`
    alter table public.styling_looks drop constraint styling_looks_user_id_fkey;
    alter table public.styling_looks add constraint styling_looks_user_id_fkey
      foreign key (user_id) references public.users(id)
  `);
  await assertGeneratedNameRejected();
  await assertUnloggedExactTargetRejected();
  assert.match(await readExpectedSha(), /^[0-9a-f]{64}$/);

  process.stdout.write([
    "styling_schema_finalization_fingerprint assertions=pass",
    "runner_context=required",
    "approval_token=required",
    "live_shape=exact-birth-and-styling-absent-only",
    "replay=exact-catalog-and-receipt-only",
    "birth_date=absent/type/null/default/generated-drift-rejected",
    "styling=old-shape/generated/fk/index/persistence/rls/acl-drift-rejected",
    "receipts=20260822-exact/20260824-absent/20260825-exact-required",
    "mutation=none-before-rejection",
    "identifiers=redacted",
    "cleanup=embedded-postgres-stopped-and-data-removed"
  ].join("\n") + "\n");
};

void run().catch((error: unknown) => {
  if (error instanceof Error) {
    process.stderr.write(`${error.name}: ${error.message}\n`);
  } else {
    process.stderr.write("Unknown styling finalization fingerprint failure\n");
  }
  process.exit(1);
});
