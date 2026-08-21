import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { z } from "zod";
import { postgresErrorSchema } from "./apple-app-store-notification.db-assertions";
import { readCapabilities } from "./monetization-schema-reconciliation.assertions";
import {
  monetizationSchemaReconciliationMigration,
  startDisposableReconciliationDatabase
} from "./monetization-schema-reconciliation.db-harness";
import { applyMonetizationSchemaReconciliation } from "./monetization-schema-reconciliation.runner";

const expectDatabaseError = async (
  operation: () => Promise<unknown>,
  expectedMessage: string
): Promise<void> => {
  await assert.rejects(operation, (error: unknown) => {
    const parsed = postgresErrorSchema.safeParse(error);
    return parsed.success && parsed.data.message === expectedMessage;
  });
};

const assertDriftRejected = async (mutationSql: string): Promise<void> => {
  const database = await startDisposableReconciliationDatabase("production_partial");
  try {
    await database.client.query(mutationSql);
    await expectDatabaseError(
      () => database.applyReconciliation(),
      "monetization_catalog_drift"
    );
    const capabilities = await readCapabilities(database.client);
    assert.equal(capabilities.marker_table, false);
    assert.equal(capabilities.change_record_table, false);
    assert.equal(capabilities.apple_transactions, false);
  } finally {
    await database.stop();
  }
};

const assertRunnerContextRequired = async (): Promise<void> => {
  const database = await startDisposableReconciliationDatabase("production_partial");
  try {
    const migrationPath = resolve(
      process.cwd(),
      "..",
      "supabase",
      "migrations",
      monetizationSchemaReconciliationMigration
    );
    const migrationSql = await readFile(migrationPath, "utf8");
    await expectDatabaseError(
      () => database.client.query(migrationSql),
      "monetization_reconciliation_runner_context_required"
    );
    assert.equal((await readCapabilities(database.client)).apple_transactions, false);
  } finally {
    await database.stop();
  }
};

const assertApprovalRequired = async (): Promise<void> => {
  const database = await startDisposableReconciliationDatabase("production_partial");
  try {
    await assert.rejects(
      () => applyMonetizationSchemaReconciliation(database.client, "approval-not-provided"),
      (error: unknown) => error instanceof z.ZodError
    );
    assert.equal((await readCapabilities(database.client)).apple_transactions, false);
  } finally {
    await database.stop();
  }
};

const run = async (): Promise<void> => {
  await assertRunnerContextRequired();
  await assertApprovalRequired();
  await assertDriftRejected(`
    create schema supabase_migrations;
    create table supabase_migrations.schema_migrations(version text primary key);
  `);
  await assertDriftRejected(`
    alter table public.thread_ledger_entries
      drop constraint thread_ledger_entries_reason_check;
    alter table public.thread_ledger_entries
      add constraint thread_ledger_entries_reason_check
      check (reason in ('fit_analysis', 'fit_report', 'iap_purchase', 'ad_reward'));
  `);
  await assertDriftRejected(`
    alter table public.thread_ledger_entries
      drop constraint thread_ledger_entries_user_id_idempotency_key_reason_key;
    alter table public.thread_ledger_entries
      add constraint thread_ledger_entries_user_id_idempotency_key_key
      unique (user_id, idempotency_key);
  `);
  await assertDriftRejected(`
    create or replace function public.grant_admob_reward(
      p_attempt_id uuid,
      p_transaction_id text
    ) returns table(available_threads integer, status text)
    language sql security definer set search_path = public
    as $$ select 0, 'unknown_attempt'::text $$;
  `);
  process.stdout.write([
    "fingerprint_guard assertions=pass",
    "runner_context=required",
    "approval_token=required",
    "supabase_ledger=unexpected-drift",
    "wallet_reason=unexpected-drift",
    "wallet_uniqueness=unexpected-drift",
    "admob_definition=unknown-drift",
    "mutation=none-before-rejection",
    "identifiers=redacted"
  ].join("\n") + "\n");
};

void run().catch((error: unknown) => {
  if (error instanceof Error) {
    process.stderr.write(`${error.name}: ${error.message}\n`);
  } else {
    process.stderr.write("Unknown reconciliation fingerprint test error\n");
  }
  process.exit(1);
});
