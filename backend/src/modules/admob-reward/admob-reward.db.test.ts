import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import {
  countRows,
  createAttempt,
  expectPermissionDenied,
  getBalance,
  invokeGrant,
  parseConsumptionRow,
  uuidSchema
} from "./admob-reward.db-assertions";
import {
  admobDatabaseMigrations,
  startDisposableAdmobDatabase,
  withDatabaseRole
} from "./admob-reward.db-harness";
import { assertConcurrentCrossAttemptConflict } from "./admob-reward.db-race";

const run = async (): Promise<void> => {
  const database = await startDisposableAdmobDatabase();
  try {
    assert.deepEqual(database.appliedMigrations, admobDatabaseMigrations);

    const rlsResult = await database.client.query(`
      select relname, relrowsecurity
      from pg_class
      where relnamespace = 'public'::regnamespace
        and relname in (
          'thread_balances',
          'thread_ledger_entries',
          'admob_reward_attempts',
          'admob_reward_transactions'
        )
      order by relname
    `);
    assert.equal(rlsResult.rows.length, 4);
    assert.equal(rlsResult.rows.every((row) => row.relrowsecurity === true), true);

    const rpcPrivileges = await database.client.query(`
      select
        has_function_privilege('service_role', 'public.grant_admob_reward(uuid,text)', 'execute') as service_role,
        has_function_privilege('anon', 'public.grant_admob_reward(uuid,text)', 'execute') as anon,
        has_function_privilege('authenticated', 'public.grant_admob_reward(uuid,text)', 'execute') as authenticated
    `);
    assert.deepEqual(rpcPrivileges.rows, [
      { service_role: true, anon: false, authenticated: false }
    ]);

    const userId = uuidSchema.parse(randomUUID());
    const otherUserId = uuidSchema.parse(randomUUID());
    await database.client.query("insert into public.users(id) values ($1::uuid), ($2::uuid)", [
      userId,
      otherUserId
    ]);

    await expectPermissionDenied(async () => {
      await withDatabaseRole(database.client, "anon", async (roleClient) => {
        await roleClient.query("select * from public.create_admob_reward_attempt($1::uuid)", [userId]);
      });
    });
    await expectPermissionDenied(async () => {
      await withDatabaseRole(database.client, "authenticated", async (roleClient) => {
        await roleClient.query("select * from public.admob_reward_attempts");
      });
    });

    const startingBalance = await getBalance(database.client, userId);
    assert.equal(startingBalance, 36);

    const firstAttemptId = await createAttempt(database.client, userId);
    const transactionId = `db-test-${randomUUID()}`;
    const firstGrant = await invokeGrant(database.client, firstAttemptId, transactionId);
    assert.deepEqual(firstGrant, {
      kind: "row",
      httpStatus: 200,
      status: "granted",
      availableThreads: startingBalance + 1
    });
    assert.equal(
      await countRows(
        database.client,
        "select count(*) from public.thread_ledger_entries where user_id = $1::uuid and reason = 'ad_reward'",
        [userId]
      ),
      1
    );

    const replay = await invokeGrant(database.client, firstAttemptId, transactionId);
    assert.deepEqual(replay, {
      kind: "row",
      httpStatus: 200,
      status: "already_granted",
      availableThreads: startingBalance + 1
    });

    const conflictingAttemptId = await createAttempt(database.client, otherUserId);
    const conflictingGrant = await invokeGrant(database.client, conflictingAttemptId, transactionId);
    assert.deepEqual(conflictingGrant, {
      kind: "conflict",
      httpStatus: 409,
      category: "admob_transaction_attempt_conflict"
    });
    assert.equal(
      await countRows(
        database.client,
        "select count(*) from public.thread_balances where user_id = $1::uuid",
        [otherUserId]
      ),
      0
    );

    const expiredAttemptId = await createAttempt(database.client, userId);
    await database.client.query(
      "update public.admob_reward_attempts set expires_at = now() - interval '1 second' where id = $1::uuid",
      [expiredAttemptId]
    );
    const ledgerBeforeExpiredGrant = await countRows(
      database.client,
      "select count(*) from public.thread_ledger_entries where user_id = $1::uuid",
      [userId]
    );
    const expiredGrant = await invokeGrant(
      database.client,
      expiredAttemptId,
      `db-test-expired-${randomUUID()}`
    );
    assert.deepEqual(expiredGrant, {
      kind: "row",
      httpStatus: 409,
      status: "expired",
      availableThreads: startingBalance + 1
    });
    assert.equal(
      await countRows(
        database.client,
        "select count(*) from public.thread_ledger_entries where user_id = $1::uuid",
        [userId]
      ),
      ledgerBeforeExpiredGrant
    );

    const fitAnalysisResultId = uuidSchema.parse(randomUUID());
    const consumptionKey = uuidSchema.parse(randomUUID());
    await database.client.query(
      "insert into public.fit_analysis_results(id, user_id) values ($1::uuid, $2::uuid)",
      [fitAnalysisResultId, userId]
    );
    const consumeResult = await withDatabaseRole(database.client, "service_role", async (roleClient) => {
      return roleClient.query(
        "select * from public.consume_fit_report_thread($1::uuid, $2::uuid, $3::uuid)",
        [userId, consumptionKey, fitAnalysisResultId]
      );
    });
    assert.deepEqual(parseConsumptionRow(consumeResult.rows), {
      available_threads: startingBalance,
      status: "consumed"
    });
    const consumeReplayResult = await withDatabaseRole(
      database.client,
      "service_role",
      async (roleClient) => {
        return roleClient.query(
          "select * from public.consume_fit_report_thread($1::uuid, $2::uuid, $3::uuid)",
          [userId, consumptionKey, fitAnalysisResultId]
        );
      }
    );
    assert.deepEqual(parseConsumptionRow(consumeReplayResult.rows), {
      available_threads: startingBalance,
      status: "already_consumed"
    });

    await assertConcurrentCrossAttemptConflict(database);

    process.stdout.write(
      [
        "admob_reward_db assertions=pass",
        `database=${database.databaseKind}`,
        `migrations=${database.appliedMigrations.length}`,
        `initial_balance=${startingBalance}`,
        `first_grant=200/granted/${startingBalance + 1}/ledger:1`,
        `same_attempt_replay=200/already_granted/${startingBalance + 1}/ledger:1`,
        `cross_attempt_replay=409/admob_transaction_attempt_conflict/no_balance`,
        `expired_attempt=409/expired/ledger:0`,
        `fit_report_consume=200/consumed/${startingBalance}/replay:already_consumed`,
        "concurrent_cross_attempt=one_grant/one_conflict/ledger:1",
        "rls=enabled",
        "rpc_roles=service_role_only",
        "identifiers=redacted"
      ].join("\n") + "\n"
    );
  } finally {
    await database.stop();
    process.stdout.write("cleanup=embedded-postgres-stopped-and-data-removed\n");
  }
};

void run().catch((error: unknown) => {
  if (error instanceof Error) {
    process.stderr.write(`${error.name}: ${error.message}\n`);
  } else {
    process.stderr.write("Unknown database harness failure\n");
  }
  process.exit(1);
});
