import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { postgresErrorSchema } from "../thread-wallet/apple-app-store-notification.db-assertions";
import {
  readChangeRecord as readMonetizationChangeRecord,
  readSchemaMarkers
} from "../thread-wallet/monetization-schema-reconciliation.assertions";
import {
  readProfileMutationSnapshot,
  readProfileStylingCapabilities,
  readSentinelSnapshot
} from "./profile-styling-schema-reconciliation.db-assertions";
import { startDisposableProfileStylingDatabase } from "./profile-styling-schema-reconciliation.db-harness";

const run = async (): Promise<void> => {
  // Given: a known partial with existing user, wallet, and ledger sentinels.
  const database = await startDisposableProfileStylingDatabase();
  try {
    const userId = randomUUID();
    const ledgerId = randomUUID();
    await database.client.query("insert into public.users(id) values ($1::uuid)", [userId]);
    await database.client.query(`
      insert into public.thread_balances(user_id, available_threads)
      values ($1::uuid, 29)
    `, [userId]);
    await database.client.query(`
      insert into public.thread_ledger_entries(
        id, user_id, idempotency_key, amount, reason
      ) values ($1::uuid, $2::uuid, $3::uuid, -3, 'admin_adjustment')
    `, [ledgerId, userId, randomUUID()]);
    const catalogBefore = await readProfileMutationSnapshot(database.client);
    const sentinelsBefore = await readSentinelSnapshot(database.client, userId, ledgerId);
    const monetaryRecordBefore = await readMonetizationChangeRecord(database.client);
    const monetaryMarkersBefore = await readSchemaMarkers(database.client);

    // When: the runner forces a failure after migration execution and before commit.
    await assert.rejects(
      () => database.applyProfileStylingReconciliation({
        postflightMode: "fail_after_migration"
      }),
      (error: unknown) => {
        const parsed = postgresErrorSchema.safeParse(error);
        return parsed.success
          && parsed.data.message ===
            "profile_styling_reconciliation_test_postflight_failure";
      }
    );

    // Then: the transaction rolls back every schema/receipt change and preserves sentinels.
    assert.deepEqual(await readProfileMutationSnapshot(database.client), catalogBefore);
    assert.deepEqual(
      await readSentinelSnapshot(database.client, userId, ledgerId),
      sentinelsBefore
    );
    assert.deepEqual(await readMonetizationChangeRecord(database.client), monetaryRecordBefore);
    assert.deepEqual(await readSchemaMarkers(database.client), monetaryMarkersBefore);
    assert.deepEqual(await readProfileStylingCapabilities(database.client), {
      birth_date: false,
      styling_looks: false,
      change_record: false
    });
  } finally {
    await database.stop();
  }

  process.stdout.write([
    "profile_styling_late_rollback assertions=pass",
    "forced_postflight=failed-before-commit",
    "rollback=birth-date/styling-table/change-record-absent",
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
    process.stderr.write("Unknown profile/styling rollback test failure\n");
  }
  process.exit(1);
});
