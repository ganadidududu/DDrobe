import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import {
  countRows,
  invokeClientPurchase,
  invokeNotificationPurchase,
  invokeRecordOnlyNotification,
  postgresErrorSchema,
  type AppleNotificationDatabaseFixture,
  type ApplePurchaseDatabaseFixture
} from "./apple-app-store-notification.db-assertions";
import { startDisposableAppleNotificationDatabase } from "./apple-app-store-notification.db-harness";

const capabilityRowSchema = z.object({ available: z.boolean() });
const balanceRowSchema = z.object({ available_threads: z.number().int().nonnegative() });

const purchaseFixture = (
  userId: string,
  transactionId: string,
  environment: "Sandbox" | "Production" = "Production"
): ApplePurchaseDatabaseFixture => ({
  userId,
  transactionId,
  originalTransactionId: transactionId,
  productId: "com.inseong.coordit.thread.10",
  appAccountToken: userId,
  purchasedAt: "2026-08-21T00:00:00.000Z",
  environment,
  threadAmount: 10
});

const notificationFixture = (
  purchase: ApplePurchaseDatabaseFixture,
  notificationUUID = randomUUID()
): AppleNotificationDatabaseFixture => ({
  notificationUUID,
  notificationType: "ONE_TIME_CHARGE",
  subtype: null,
  environment: purchase.environment,
  purchase
});

const balanceFor = async (userId: string, databaseClient: Parameters<typeof countRows>[0]) => {
  const result = await databaseClient.query(
    "select available_threads from public.thread_balances where user_id = $1::uuid",
    [userId]
  );
  return balanceRowSchema.parse(result.rows[0]).available_threads;
};

const expectPostgresError = async (
  operation: () => Promise<unknown>,
  code: string,
  message: string
): Promise<void> => {
  await assert.rejects(operation, (error: unknown) => {
    const parsed = postgresErrorSchema.safeParse(error);
    return parsed.success && parsed.data.code === code && parsed.data.message === message;
  });
};

const run = async (): Promise<void> => {
  // Given: a fresh PostgreSQL instance with all monetary and Todo 6 forward migrations.
  const database = await startDisposableAppleNotificationDatabase();
  try {
    const capabilityResult = await database.client.query(`
      select to_regprocedure(
        'public.reconcile_apple_iap_notification(uuid,text,text,text,uuid,text,text,text,uuid,timestamptz,text,integer)'
      ) is not null as available
    `);
    assert.equal(capabilityRowSchema.parse(capabilityResult.rows[0]).available, true);

    const securityResult = await database.client.query(`
      select
        c.relrowsecurity as rls,
        has_function_privilege('service_role', 'public.reconcile_apple_iap_notification(uuid,text,text,text,uuid,text,text,text,uuid,timestamptz,text,integer)', 'execute') as service_execute,
        has_function_privilege('anon', 'public.reconcile_apple_iap_notification(uuid,text,text,text,uuid,text,text,text,uuid,timestamptz,text,integer)', 'execute') as anon_execute,
        has_function_privilege('authenticated', 'public.reconcile_apple_iap_notification(uuid,text,text,text,uuid,text,text,text,uuid,timestamptz,text,integer)', 'execute') as authenticated_execute
      from pg_class c
      where c.oid = 'public.apple_iap_notification_receipts'::regclass
    `);
    assert.deepEqual(securityResult.rows, [{
      rls: true,
      service_execute: true,
      anon_execute: false,
      authenticated_execute: false
    }]);

    // Given/When: a client settles first, followed by the same notification twice.
    const clientFirstUserId = randomUUID();
    await database.client.query("insert into public.users(id) values ($1::uuid)", [clientFirstUserId]);
    const clientFirstPurchase = purchaseFixture(clientFirstUserId, `client-first-${randomUUID()}`);
    assert.deepEqual(await invokeClientPurchase(database.client, clientFirstPurchase), {
      available_threads: 46,
      status: "credited"
    });
    const clientFirstNotification = notificationFixture(clientFirstPurchase);
    assert.deepEqual(await invokeNotificationPurchase(database.client, clientFirstNotification), {
      available_threads: 46,
      status: "already_credited"
    });
    assert.deepEqual(await invokeNotificationPurchase(database.client, clientFirstNotification), {
      available_threads: 46,
      status: "already_processed"
    });
    // Then: the client-first order leaves one ledger credit and one receipt.
    assert.equal(await countRows(database.client,
      "select count(*) from public.thread_ledger_entries where user_id=$1::uuid and reason='iap_purchase'",
      [clientFirstUserId]), 1);
    assert.equal(await countRows(database.client,
      "select count(*) from public.apple_iap_notification_receipts where notification_uuid=$1::uuid",
      [clientFirstNotification.notificationUUID]), 1);

    // Given/When: a notification settles first, followed by the client retry.
    const notificationFirstUserId = randomUUID();
    await database.client.query("insert into public.users(id) values ($1::uuid)", [notificationFirstUserId]);
    const notificationFirstPurchase = purchaseFixture(
      notificationFirstUserId,
      `notification-first-${randomUUID()}`,
      "Sandbox"
    );
    assert.deepEqual(await invokeNotificationPurchase(
      database.client,
      notificationFixture(notificationFirstPurchase)
    ), { available_threads: 46, status: "credited" });
    assert.deepEqual(await invokeClientPurchase(database.client, notificationFirstPurchase), {
      available_threads: 46,
      status: "already_credited"
    });
    // Then: notification-first also creates exactly one ledger credit.
    assert.equal(await countRows(database.client,
      "select count(*) from public.thread_ledger_entries where user_id=$1::uuid and reason='iap_purchase'",
      [notificationFirstUserId]), 1);

    // Given/When: client and notification race on the same transaction using separate connections.
    const raceUserId = randomUUID();
    await database.client.query("insert into public.users(id) values ($1::uuid)", [raceUserId]);
    const racePurchase = purchaseFixture(raceUserId, `race-${randomUUID()}`);
    const raceNotification = notificationFixture(racePurchase);
    const clientConnection = await database.openClient();
    const notificationConnection = await database.openClient();
    const raceResults = await Promise.all([
      invokeClientPurchase(clientConnection, racePurchase),
      invokeNotificationPurchase(notificationConnection, raceNotification)
    ]);
    assert.deepEqual(raceResults.map((result) => result.status).sort(), [
      "already_credited",
      "credited"
    ]);
    // Then: the concurrent delivery produces one exact package credit and one receipt.
    assert.equal(await balanceFor(raceUserId, database.client), 46);
    assert.equal(await countRows(database.client,
      "select count(*) from public.thread_ledger_entries where user_id=$1::uuid and reason='iap_purchase'",
      [raceUserId]), 1);
    assert.equal(await countRows(database.client,
      "select count(*) from public.apple_iap_notification_receipts where notification_uuid=$1::uuid",
      [raceNotification.notificationUUID]), 1);

    // Given/When: a verified record-only test notification is delivered twice.
    const testNotificationUUID = randomUUID();
    assert.deepEqual(await invokeRecordOnlyNotification(
      database.client,
      testNotificationUUID,
      "Production"
    ), { status: "processed" });
    assert.deepEqual(await invokeRecordOnlyNotification(
      database.client,
      testNotificationUUID,
      "Production"
    ), { status: "already_processed" });
    // Then: notification UUID de-duplication stores exactly one receipt.
    assert.equal(await countRows(database.client,
      "select count(*) from public.apple_iap_notification_receipts where notification_uuid=$1::uuid",
      [testNotificationUUID]), 1);

    // Given/When: an invalid product amount reaches the database safety boundary.
    const invalidUserId = randomUUID();
    await database.client.query("insert into public.users(id) values ($1::uuid)", [invalidUserId]);
    const invalidPurchase = { ...purchaseFixture(invalidUserId, `invalid-${randomUUID()}`), threadAmount: 20 };
    const invalidNotification = notificationFixture(invalidPurchase);
    await expectPostgresError(
      () => invokeNotificationPurchase(database.client, invalidNotification),
      "22023",
      "apple_product_amount_invalid"
    );
    // Then: the failed statement leaves no balance, ledger, transaction, or receipt mutation.
    assert.equal(await countRows(database.client,
      "select count(*) from public.thread_balances where user_id=$1::uuid", [invalidUserId]), 0);
    assert.equal(await countRows(database.client,
      "select count(*) from public.thread_ledger_entries where user_id=$1::uuid", [invalidUserId]), 0);
    assert.equal(await countRows(database.client,
      "select count(*) from public.apple_iap_notification_receipts where notification_uuid=$1::uuid",
      [invalidNotification.notificationUUID]), 0);

    process.stdout.write([
      "apple_notification_db assertions=pass",
      "client_first=credited_then_already_credited_then_already_processed/ledger:1/receipt:1",
      "notification_first=credited_then_client_already_credited/ledger:1",
      "concurrent_race=one_credited_one_already_credited/balance:46/ledger:1/receipt:1",
      "record_only_replay=processed_then_already_processed/receipt:1",
      "invalid_amount=22023/no_balance/no_ledger/no_receipt",
      "rls=enabled",
      "rpc_roles=service_role_only",
      "identifiers=redacted"
    ].join("\n") + "\n");
  } finally {
    await database.stop();
    process.stdout.write("cleanup=embedded-postgres-stopped-and-data-removed\n");
  }
};

void run().catch((error: unknown) => {
  if (error instanceof Error) {
    process.stderr.write(`${error.name}: ${error.message}\n`);
  } else {
    process.stderr.write("Unknown Apple notification database test failure\n");
  }
  process.exit(1);
});
