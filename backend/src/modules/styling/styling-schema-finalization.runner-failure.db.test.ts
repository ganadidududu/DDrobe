import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { postgresErrorSchema } from "../thread-wallet/apple-app-store-notification.db-assertions";
import {
  readChangeRecord as readMonetizationChangeRecord,
  readSchemaMarkers
} from "../thread-wallet/monetization-schema-reconciliation.assertions";
import {
  readStylingFinalizationCapabilities,
  readStylingFinalizationMutationSnapshot,
  readStylingFinalizationSentinelSnapshot
} from "./styling-schema-finalization.db-assertions";
import { startDisposableStylingFinalizationDatabase } from "./styling-schema-finalization.db-harness";

const run = async (): Promise<void> => {
  // Given: the observed live shape with existing birth, wallet, and ledger sentinels.
  const database = await startDisposableStylingFinalizationDatabase();
  try {
    const userId = randomUUID();
    const ledgerId = randomUUID();
    await database.client.query(`
      insert into public.users(id, birth_date)
      values ($1::uuid, '1988-11-03'::date)
    `, [userId]);
    await database.client.query(`
      insert into public.thread_balances(user_id, available_threads)
      values ($1::uuid, 29)
    `, [userId]);
    await database.client.query(`
      insert into public.thread_ledger_entries(
        id, user_id, idempotency_key, amount, reason
      ) values ($1::uuid, $2::uuid, $3::uuid, -3, 'admin_adjustment')
    `, [ledgerId, userId, randomUUID()]);
    const catalogBefore = await readStylingFinalizationMutationSnapshot(database.client);
    const sentinelsBefore = await readStylingFinalizationSentinelSnapshot(
      database.client,
      userId,
      ledgerId
    );
    const monetaryRecordBefore = await readMonetizationChangeRecord(database.client);
    const monetaryMarkersBefore = await readSchemaMarkers(database.client);

    // When: postflight is forced to fail after migration execution and before commit.
    await assert.rejects(
      () => database.applyStylingFinalization({
        postflightMode: "fail_after_migration"
      }),
      (error: unknown) => {
        const parsed = postgresErrorSchema.safeParse(error);
        return parsed.success
          && parsed.data.message === "styling_schema_finalization_test_postflight_failure";
      }
    );

    // Then: styling and its receipt roll back while pre-existing birth and rows remain.
    assert.deepEqual(
      await readStylingFinalizationMutationSnapshot(database.client),
      catalogBefore
    );
    assert.deepEqual(
      await readStylingFinalizationSentinelSnapshot(database.client, userId, ledgerId),
      sentinelsBefore
    );
    assert.deepEqual(await readMonetizationChangeRecord(database.client), monetaryRecordBefore);
    assert.deepEqual(await readSchemaMarkers(database.client), monetaryMarkersBefore);
    assert.deepEqual(await readStylingFinalizationCapabilities(database.client), {
      birth_date_exact: true,
      styling_looks: false,
      receipt_20260824: false,
      receipt_20260825: false
    });
  } finally {
    await database.stop();
  }

  process.stdout.write([
    "styling_schema_finalization_rollback assertions=pass",
    "forced_postflight=failed-before-commit",
    "rollback=styling-table-and-20260825-receipt-absent",
    "birth_date=pre-existing-definition-and-value-unchanged",
    "sentinels=user/wallet/ledger-unchanged",
    "monetization=receipt-and-markers-unchanged",
    "identifiers=redacted",
    "cleanup=embedded-postgres-stopped-and-data-removed"
  ].join("\n") + "\n");
};

void run().catch((error: unknown) => {
  if (error instanceof Error) {
    process.stderr.write(`${error.name}: ${error.message}\n`);
  } else {
    process.stderr.write("Unknown styling finalization rollback failure\n");
  }
  process.exit(1);
});
