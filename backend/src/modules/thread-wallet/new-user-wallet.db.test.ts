import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { startDisposableReconciliationDatabase } from "./monetization-schema-reconciliation.db-harness";

const migrationName = "20260826_seed_new_user_thread_balance.sql";

const run = async (): Promise<void> => {
  const database = await startDisposableReconciliationDatabase("fresh");
  try {
    await database.applyReconciliation();
    const existingUserID = randomUUID();
    await database.client.query("insert into public.users(id) values ($1::uuid)", [existingUserID]);
    await database.client.query(
      "insert into public.thread_balances(user_id, available_threads) values ($1::uuid, 32)",
      [existingUserID]
    );

    const migration = await readFile(
      resolve(process.cwd(), "..", "supabase", "migrations", migrationName),
      "utf8"
    );
    await database.client.query(migration);
    await database.client.query(migration);

    const newUserID = randomUUID();
    await database.client.query("insert into public.users(id) values ($1::uuid)", [newUserID]);
    const newBalance = await database.client.query<{ available_threads: number }>(
      "select available_threads from public.thread_balances where user_id = $1::uuid",
      [newUserID]
    );
    assert.equal(newBalance.rows[0]?.available_threads, 3);

    await database.client.query(
      "insert into public.users(id) values ($1::uuid) on conflict (id) do nothing",
      [existingUserID]
    );
    const existingBalance = await database.client.query<{ available_threads: number }>(
      "select available_threads from public.thread_balances where user_id = $1::uuid",
      [existingUserID]
    );
    assert.equal(existingBalance.rows[0]?.available_threads, 32);
    process.stdout.write("apply_replay=pass new_user_balance=3 existing_balance=32 assertions=pass\n");
  } finally {
    await database.stop();
    process.stdout.write("cleanup=embedded-postgres-stopped-and-data-removed\n");
  }
};

run().catch((error: unknown) => {
  process.stderr.write(`${error instanceof Error ? error.message : "unknown failure"}\n`);
  process.exitCode = 1;
});
