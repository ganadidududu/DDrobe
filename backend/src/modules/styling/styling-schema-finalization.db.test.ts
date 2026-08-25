import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { z } from "zod";
import {
  expectPermissionDenied,
  uuidSchema
} from "../admob-reward/admob-reward.db-assertions";
import { withDatabaseRole } from "../admob-reward/admob-reward.db-harness";
import {
  readChangeRecord as readMonetizationChangeRecord,
  readPublicTableNames,
  readSchemaMarkers
} from "../thread-wallet/monetization-schema-reconciliation.assertions";
import { assertExactProfileStylingCatalog } from "./profile-styling-schema-reconciliation.catalog-assertions";
import { readUserColumnNames } from "./profile-styling-schema-reconciliation.db-assertions";
import {
  readBirthDateDefinition,
  readStylingFinalizationCapabilities,
  readStylingFinalizationChangeRecord,
  readStylingFinalizationSentinelSnapshot
} from "./styling-schema-finalization.db-assertions";
import { startDisposableStylingFinalizationDatabase } from "./styling-schema-finalization.db-harness";
import { stylingSchemaFinalizationFilename } from "./styling-schema-finalization.runner";

const stylingLookSchema = z.object({
  id: uuidSchema,
  user_id: uuidSchema,
  name: z.string(),
  name_ko: z.string(),
  mood: z.string(),
  palette: z.array(z.string()),
  ai_reasoning: z.string(),
  fit_score: z.string().nullable(),
  item_ids: z.array(z.string()),
  prompt: z.string(),
  created_at: z.date()
});

const readExpectedMigrationSha = async (): Promise<string> => {
  const migrationPath = resolve(
    process.cwd(),
    "..",
    "supabase",
    "migrations",
    stylingSchemaFinalizationFilename
  );
  const migrationSql = await readFile(migrationPath, "utf8");
  return createHash("sha256").update(migrationSql, "utf8").digest("hex");
};

const assertServiceRoleLookLifecycle = async (
  database: Awaited<ReturnType<typeof startDisposableStylingFinalizationDatabase>>,
  userId: string
): Promise<void> => {
  const lifecycle = await withDatabaseRole(database.client, "service_role", async (client) => {
    const insertedResult = await client.query(`
      insert into public.styling_looks(user_id, name, name_ko)
      values ($1::uuid, 'Release Look', '릴리스 룩')
      returning *
    `, [userId]);
    const inserted = stylingLookSchema.parse(insertedResult.rows[0]);
    const selectedResult = await client.query(
      "select * from public.styling_looks where id = $1::uuid",
      [inserted.id]
    );
    const selected = stylingLookSchema.parse(selectedResult.rows[0]);
    const updatedResult = await client.query(`
      update public.styling_looks set mood = 'verified'
      where id = $1::uuid returning *
    `, [inserted.id]);
    const updated = stylingLookSchema.parse(updatedResult.rows[0]);
    const deletedResult = await client.query(`
      delete from public.styling_looks where id = $1::uuid returning id
    `, [inserted.id]);
    return {
      inserted,
      selected,
      updated,
      deletedId: uuidSchema.parse(deletedResult.rows[0]?.id)
    };
  });

  assert.deepEqual(lifecycle.selected, lifecycle.inserted);
  assert.equal(lifecycle.inserted.mood, "");
  assert.deepEqual(lifecycle.inserted.palette, []);
  assert.deepEqual(lifecycle.inserted.item_ids, []);
  assert.equal(lifecycle.inserted.prompt, "");
  assert.equal(lifecycle.updated.mood, "verified");
  assert.equal(lifecycle.deletedId, lifecycle.inserted.id);
};

const run = async (): Promise<void> => {
  // Given: the exact observed live shape with monetary and row sentinels.
  const database = await startDisposableStylingFinalizationDatabase();
  try {
    const userId = randomUUID();
    const ledgerId = randomUUID();
    const idempotencyKey = randomUUID();
    await database.client.query(`
      insert into public.users(id, birth_date)
      values ($1::uuid, '1994-05-17'::date)
    `, [userId]);
    await database.client.query(`
      insert into public.thread_balances(user_id, available_threads)
      values ($1::uuid, 41)
    `, [userId]);
    await database.client.query(`
      insert into public.thread_ledger_entries(
        id, user_id, idempotency_key, amount, reason
      ) values ($1::uuid, $2::uuid, $3::uuid, 4, 'admin_adjustment')
    `, [ledgerId, userId, idempotencyKey]);

    const tablesBefore = await readPublicTableNames(database.client);
    const userColumnsBefore = await readUserColumnNames(database.client);
    const birthDateBefore = await readBirthDateDefinition(database.client);
    const sentinelBefore = await readStylingFinalizationSentinelSnapshot(
      database.client,
      userId,
      ledgerId
    );
    const monetaryRecordBefore = await readMonetizationChangeRecord(database.client);
    const monetaryMarkersBefore = await readSchemaMarkers(database.client);
    assert.equal(database.stylingBaseline, "observed_live");
    assert.deepEqual(await readStylingFinalizationCapabilities(database.client), {
      birth_date_exact: true,
      styling_looks: false,
      receipt_20260824: false,
      receipt_20260825: false
    });

    // When: the styling-only repair applies once and then replays exactly.
    const firstRun = await database.applyStylingFinalization();
    const recordAfterFirstRun = await readStylingFinalizationChangeRecord(database.client);
    const replayRun = await database.applyStylingFinalization();
    const recordAfterReplay = await readStylingFinalizationChangeRecord(database.client);

    // Then: only styling and its receipt are added; birth and rows are preserved.
    assert.deepEqual(await readStylingFinalizationCapabilities(database.client), {
      birth_date_exact: true,
      styling_looks: true,
      receipt_20260824: false,
      receipt_20260825: true
    });
    assert.equal(firstRun.disposition, "reconciled_observed_partial");
    assert.deepEqual(replayRun, firstRun);
    assert.deepEqual(recordAfterReplay, recordAfterFirstRun);
    assert.equal(recordAfterReplay.migration_sha256, await readExpectedMigrationSha());
    assert.deepEqual(
      (await readPublicTableNames(database.client)).filter(
        (tableName) => !tablesBefore.includes(tableName)
      ),
      ["styling_looks"]
    );
    assert.deepEqual(
      (await readUserColumnNames(database.client)).filter(
        (columnName) => !userColumnsBefore.includes(columnName)
      ),
      []
    );
    assert.deepEqual(await readBirthDateDefinition(database.client), birthDateBefore);
    assert.deepEqual(
      await readStylingFinalizationSentinelSnapshot(database.client, userId, ledgerId),
      sentinelBefore
    );
    assert.deepEqual(await readMonetizationChangeRecord(database.client), monetaryRecordBefore);
    assert.deepEqual(await readSchemaMarkers(database.client), monetaryMarkersBefore);
    await assertExactProfileStylingCatalog(database.client);
    await assertServiceRoleLookLifecycle(database, userId);
    await expectPermissionDenied(() => withDatabaseRole(
      database.client,
      "anon",
      (client) => client.query("select count(*) from public.styling_looks")
    ));
    await expectPermissionDenied(() => withDatabaseRole(
      database.client,
      "authenticated",
      (client) => client.query("select count(*) from public.styling_looks")
    ));
  } finally {
    await database.stop();
  }

  process.stdout.write([
    "styling_schema_finalization assertions=pass",
    "live=exact-birth/styling-absent-to-exact",
    "replay=filename-sha-disposition-applied_at-stable",
    "catalog=styling-columns/fk/index/rls/service-crud-only",
    "birth_date=pre-existing-definition-and-value-unchanged",
    "sentinels=user/wallet/ledger-rows-unchanged",
    "scope=one-table/zero-user-columns/one-change-record",
    "identifiers=redacted",
    "cleanup=embedded-postgres-stopped-and-data-removed"
  ].join("\n") + "\n");
};

void run().catch((error: unknown) => {
  if (error instanceof Error) {
    process.stderr.write(`${error.name}: ${error.message}\n`);
  } else {
    process.stderr.write("Unknown styling schema finalization failure\n");
  }
  process.exit(1);
});
