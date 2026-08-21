import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { countRows, createAttempt, invokeGrant, uuidSchema } from "./admob-reward.db-assertions";
import type { DisposableAdmobDatabase } from "./admob-reward.db-harness";

export const assertConcurrentCrossAttemptConflict = async (
  database: DisposableAdmobDatabase
): Promise<void> => {
  const firstUserId = uuidSchema.parse(randomUUID());
  const secondUserId = uuidSchema.parse(randomUUID());
  await database.client.query("insert into public.users(id) values ($1::uuid), ($2::uuid)", [
    firstUserId,
    secondUserId
  ]);

  const firstAttemptId = await createAttempt(database.client, firstUserId);
  const secondAttemptId = await createAttempt(database.client, secondUserId);
  const firstClient = await database.openClient();
  const secondClient = await database.openClient();
  const sharedTransactionId = `db-test-race-${randomUUID()}`;

  const results = await Promise.all([
    invokeGrant(firstClient, firstAttemptId, sharedTransactionId),
    invokeGrant(secondClient, secondAttemptId, sharedTransactionId)
  ]);
  const outcomes = results
    .map((result) =>
      result.kind === "row" ? `${result.httpStatus}/${result.status}` : `${result.httpStatus}/${result.category}`
    )
    .sort();
  assert.deepEqual(outcomes, ["200/granted", "409/admob_transaction_attempt_conflict"]);

  assert.equal(
    await countRows(
      database.client,
      "select count(*) from public.thread_ledger_entries where user_id in ($1::uuid, $2::uuid) and reason = 'ad_reward'",
      [firstUserId, secondUserId]
    ),
    1
  );
  assert.equal(
    await countRows(
      database.client,
      "select count(*) from public.thread_balances where user_id in ($1::uuid, $2::uuid)",
      [firstUserId, secondUserId]
    ),
    1
  );
};
