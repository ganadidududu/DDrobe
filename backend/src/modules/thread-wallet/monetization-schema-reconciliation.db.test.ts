import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { assertReconciledAdmobAtomicity } from "./monetization-schema-reconciliation.admob-scenario";
import { assertReconciledAppleAtomicity } from "./monetization-schema-reconciliation.apple-scenario";
import {
  assertReconciledSecurity,
  monetizationSchemaMarkers,
  readCapabilities,
  readChangeRecord,
  readPublicTableNames,
  readSchemaMarkers,
  readWalletSnapshot
} from "./monetization-schema-reconciliation.assertions";
import {
  monetizationSchemaReconciliationMigration,
  startDisposableReconciliationDatabase
} from "./monetization-schema-reconciliation.db-harness";

const readExpectedMigrationSha = async (): Promise<string> => {
  const migrationPath = resolve(
    process.cwd(),
    "..",
    "supabase",
    "migrations",
    monetizationSchemaReconciliationMigration
  );
  const migrationSql = await readFile(migrationPath, "utf8");
  return createHash("sha256").update(migrationSql, "utf8").digest("hex");
};

const runProductionPartialScenario = async (): Promise<void> => {
  const database = await startDisposableReconciliationDatabase("production_partial");
  try {
    const preservedUserId = randomUUID();
    const ledgerKey = randomUUID();
    const fitResultId = randomUUID();
    await database.client.query("insert into public.users(id) values ($1::uuid)", [preservedUserId]);
    await database.client.query(
      "insert into public.fit_analysis_results(id,user_id) values ($1::uuid,$2::uuid)",
      [fitResultId, preservedUserId]
    );
    await database.client.query(
      "insert into public.thread_balances(user_id,available_threads) values ($1::uuid,19)",
      [preservedUserId]
    );
    await database.client.query(`
      insert into public.thread_ledger_entries(
        user_id,idempotency_key,fit_analysis_result_id,amount,reason
      ) values ($1::uuid,$2::uuid,$3::uuid,-1,'fit_report')
    `, [preservedUserId, ledgerKey, fitResultId]);
    await database.client.query(
      "insert into public.admob_reward_attempts(user_id) values ($1::uuid)",
      [preservedUserId]
    );

    const capabilitiesBefore = await readCapabilities(database.client);
    assert.deepEqual(capabilitiesBefore, {
      apple_transactions: false,
      apple_notifications: false,
      marker_table: false,
      change_record_table: false,
      supabase_migration_ledger: false,
      admob_hardened: false,
      birth_date: false,
      styling_looks: false
    });
    const tablesBefore = await readPublicTableNames(database.client);
    const walletBefore = await readWalletSnapshot(database.client, preservedUserId);
    process.stdout.write("partial_preflight=apple_absent/admob_stale/wallet_present\n");

    const firstRun = await database.applyReconciliation();
    const markersAfterFirstApply = await readSchemaMarkers(database.client);
    const changeRecordAfterFirstApply = await readChangeRecord(database.client);
    const replayRun = await database.applyReconciliation();
    const markersAfterReplay = await readSchemaMarkers(database.client);
    const changeRecordAfterReplay = await readChangeRecord(database.client);

    assert.deepEqual(await readCapabilities(database.client), {
      apple_transactions: true,
      apple_notifications: true,
      marker_table: true,
      change_record_table: true,
      supabase_migration_ledger: false,
      admob_hardened: true,
      birth_date: false,
      styling_looks: false
    });
    assert.deepEqual(await readWalletSnapshot(database.client, preservedUserId), walletBefore);
    assert.deepEqual(markersAfterReplay, markersAfterFirstApply);
    assert.deepEqual(changeRecordAfterReplay, changeRecordAfterFirstApply);
    assert.equal(changeRecordAfterReplay.migration_sha256, await readExpectedMigrationSha());
    assert.equal(changeRecordAfterReplay.disposition, "reconciled_observed_partial");
    assert.deepEqual(firstRun, replayRun);
    assert.deepEqual(
      markersAfterReplay.map(({ component, version }) => ({ component, version })),
      [...monetizationSchemaMarkers].sort((left, right) => left.component.localeCompare(right.component))
    );
    const addedTables = (await readPublicTableNames(database.client))
      .filter((tableName) => !tablesBefore.includes(tableName));
    assert.deepEqual(addedTables, [
      "apple_iap_notification_receipts",
      "apple_iap_transactions",
      "coordit_monetization_schema_versions",
      "coordit_schema_change_records"
    ]);
    await assertReconciledSecurity(database.client);
    await assertReconciledAdmobAtomicity(database);
    await assertReconciledAppleAtomicity(database);
  } finally {
    await database.stop();
  }
};

const runFreshScenario = async (): Promise<void> => {
  const database = await startDisposableReconciliationDatabase("fresh");
  try {
    const firstRun = await database.applyReconciliation();
    const firstMarkers = await readSchemaMarkers(database.client);
    const firstRecord = await readChangeRecord(database.client);
    const replayRun = await database.applyReconciliation();
    assert.deepEqual(await readSchemaMarkers(database.client), firstMarkers);
    assert.deepEqual(await readChangeRecord(database.client), firstRecord);
    assert.equal(firstRecord.migration_sha256, await readExpectedMigrationSha());
    assert.equal(firstRecord.disposition, "verified_exact_target");
    assert.deepEqual(firstRun, replayRun);
    const capabilities = await readCapabilities(database.client);
    assert.equal(capabilities.admob_hardened, true);
    assert.equal(capabilities.supabase_migration_ledger, false);
    await assertReconciledSecurity(database.client);
    await assertReconciledAdmobAtomicity(database);
    await assertReconciledAppleAtomicity(database);
  } finally {
    await database.stop();
  }
};

const run = async (): Promise<void> => {
  await runProductionPartialScenario();
  await runFreshScenario();
  process.stdout.write([
    "monetization_schema_reconciliation assertions=pass",
    "partial=idempotent/wallet-preserved/admob-hardened/apple-installed",
    "fresh=ordered-migrations-plus-reconciliation-idempotent/atomicity-pass",
    "change_record=filename-sha-disposition-stable-on-replay",
    "admob=replay/expired/race-one-credit/fit-report-one-spend",
    "apple=replay/cross-account-conflict/race-one-credit",
    "invalid=apple-product-amount-rejected/no-balance-ledger-transaction-receipt",
    "unrelated=styling-looks-and-birth-date-untouched",
    "identifiers=redacted",
    "cleanup=embedded-postgres-stopped-and-data-removed"
  ].join("\n") + "\n");
};

void run().catch((error: unknown) => {
  if (error instanceof Error) {
    process.stderr.write(`${error.name}: ${error.message}\n`);
  } else {
    process.stderr.write("Unknown monetization schema reconciliation failure\n");
  }
  process.exit(1);
});
