import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import { postgresErrorSchema } from "./apple-app-store-notification.db-assertions";
import {
  readCapabilities,
  readWalletSnapshot
} from "./monetization-schema-reconciliation.assertions";
import { startDisposableReconciliationDatabase } from "./monetization-schema-reconciliation.db-harness";

const scenarioSchema = z.enum(["late-rollback", "catalog-drift", "sha-mismatch"]);

const expectDatabaseError = async (
  operation: () => Promise<unknown>,
  expectedMessage: string
): Promise<void> => {
  await assert.rejects(operation, (error: unknown) => {
    const parsed = postgresErrorSchema.safeParse(error);
    return parsed.success && parsed.data.message === expectedMessage;
  });
};

const assertLateFailureRollback = async (): Promise<void> => {
  const database = await startDisposableReconciliationDatabase("production_partial");
  try {
    const userId = randomUUID();
    await database.client.query("insert into public.users(id) values ($1::uuid)", [userId]);
    await database.client.query(
      "insert into public.thread_balances(user_id,available_threads) values ($1::uuid,23)",
      [userId]
    );
    const walletBefore = await readWalletSnapshot(database.client, userId);
    const capabilitiesBefore = await readCapabilities(database.client);

    await expectDatabaseError(
      () => database.applyReconciliation({ postflightMode: "fail_after_migration" }),
      "monetization_reconciliation_test_postflight_failure"
    );

    assert.deepEqual(await readWalletSnapshot(database.client, userId), walletBefore);
    assert.deepEqual(await readCapabilities(database.client), capabilitiesBefore);
    process.stdout.write("late_rollback=runner_failure/all_schema_and_wallet_changes_rolled_back\n");
  } finally {
    await database.stop();
  }
};

const assertCatalogDriftRejected = async (): Promise<void> => {
  const database = await startDisposableReconciliationDatabase("production_partial");
  try {
    await database.client.query("create table public.apple_iap_transactions(id uuid primary key)");
    await expectDatabaseError(
      () => database.applyReconciliation(),
      "monetization_catalog_drift"
    );
    assert.equal((await readCapabilities(database.client)).marker_table, false);
    process.stdout.write("catalog_drift=preflight_rejected_before_markers\n");
  } finally {
    await database.stop();
  }
};

const assertShaMismatchRejected = async (): Promise<void> => {
  const database = await startDisposableReconciliationDatabase("production_partial");
  try {
    await database.client.query(`
      create table public.coordit_schema_change_records (
        migration_version text primary key
          check (migration_version ~ '^[0-9]{8}$'),
        migration_filename text not null unique
          check (btrim(migration_filename) <> ''),
        migration_sha256 text not null
          check (migration_sha256 ~ '^[0-9a-f]{64}$'),
        disposition text not null
          check (disposition in ('reconciled_observed_partial', 'verified_exact_target')),
        applied_at timestamptz not null default now()
      );
      alter table public.coordit_schema_change_records enable row level security;
      revoke all on table public.coordit_schema_change_records from service_role;
      grant select on table public.coordit_schema_change_records to service_role;
      insert into public.coordit_schema_change_records(
        migration_version,
        migration_filename,
        migration_sha256,
        disposition
      ) values (
        '20260822',
        '20260822_reconcile_monetization_release_schema.sql',
        repeat('0', 64),
        'reconciled_observed_partial'
      );
    `);
    await expectDatabaseError(
      () => database.applyReconciliation(),
      "monetization_schema_change_record_conflict"
    );
    assert.equal((await readCapabilities(database.client)).apple_transactions, false);
    process.stdout.write("sha_mismatch=same_version_rejected/no_apple_mutation\n");
  } finally {
    await database.stop();
  }
};

const assertNever = (value: never): never => {
  throw new TypeError(`Unexpected reconciliation failure scenario: ${String(value)}`);
};

const run = async (): Promise<void> => {
  const scenario = scenarioSchema.parse(process.argv[2]);
  switch (scenario) {
    case "late-rollback":
      await assertLateFailureRollback();
      return;
    case "catalog-drift":
      await assertCatalogDriftRejected();
      return;
    case "sha-mismatch":
      await assertShaMismatchRejected();
      return;
    default:
      assertNever(scenario);
  }
};

void run().catch((error: unknown) => {
  if (error instanceof Error) {
    process.stderr.write(`${error.name}: ${error.message}\n`);
  } else {
    process.stderr.write("Unknown reconciliation runner failure test error\n");
  }
  process.exit(1);
});
