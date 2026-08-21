import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import {
  countRows,
  createAttempt,
  invokeGrant,
  parseConsumptionRow,
  uuidSchema
} from "../admob-reward/admob-reward.db-assertions";
import { assertConcurrentCrossAttemptConflict } from "../admob-reward/admob-reward.db-race";
import { withDatabaseRole } from "../admob-reward/admob-reward.db-harness";
import type { DisposableReconciliationDatabase } from "./monetization-schema-reconciliation.db-harness";

export const assertReconciledAdmobAtomicity = async (
  database: DisposableReconciliationDatabase
): Promise<void> => {
  const userId = uuidSchema.parse(randomUUID());
  const otherUserId = uuidSchema.parse(randomUUID());
  await database.client.query("insert into public.users(id) values ($1::uuid), ($2::uuid)", [
    userId,
    otherUserId
  ]);
  const attemptId = await createAttempt(database.client, userId);
  const transactionId = `reconcile-admob-${randomUUID()}`;
  assert.deepEqual(await invokeGrant(database.client, attemptId, transactionId), {
    kind: "row",
    httpStatus: 200,
    status: "granted",
    availableThreads: 37
  });
  assert.deepEqual(await invokeGrant(database.client, attemptId, transactionId), {
    kind: "row",
    httpStatus: 200,
    status: "already_granted",
    availableThreads: 37
  });

  const conflictingAttemptId = await createAttempt(database.client, otherUserId);
  assert.deepEqual(await invokeGrant(database.client, conflictingAttemptId, transactionId), {
    kind: "conflict",
    httpStatus: 409,
    category: "admob_transaction_attempt_conflict"
  });
  assert.equal(await countRows(
    database.client,
    "select count(*) from public.thread_balances where user_id=$1::uuid",
    [otherUserId]
  ), 0);

  const expiredAttemptId = await createAttempt(database.client, userId);
  await database.client.query(
    "update public.admob_reward_attempts set expires_at=now()-interval '1 second' where id=$1::uuid",
    [expiredAttemptId]
  );
  assert.deepEqual(await invokeGrant(
    database.client,
    expiredAttemptId,
    `reconcile-expired-${randomUUID()}`
  ), {
    kind: "row",
    httpStatus: 409,
    status: "expired",
    availableThreads: 37
  });
  assert.equal(await countRows(
    database.client,
    "select count(*) from public.thread_ledger_entries where user_id=$1::uuid and reason='ad_reward'",
    [userId]
  ), 1);

  const fitResultId = uuidSchema.parse(randomUUID());
  const consumptionKey = uuidSchema.parse(randomUUID());
  await database.client.query(
    "insert into public.fit_analysis_results(id,user_id) values ($1::uuid,$2::uuid)",
    [fitResultId, userId]
  );
  const consume = async () => withDatabaseRole(database.client, "service_role", async (roleClient) => {
    return roleClient.query(
      "select * from public.consume_fit_report_thread($1::uuid,$2::uuid,$3::uuid)",
      [userId, consumptionKey, fitResultId]
    );
  });
  assert.deepEqual(parseConsumptionRow((await consume()).rows), {
    available_threads: 36,
    status: "consumed"
  });
  assert.deepEqual(parseConsumptionRow((await consume()).rows), {
    available_threads: 36,
    status: "already_consumed"
  });
  await assertConcurrentCrossAttemptConflict(database);
};
