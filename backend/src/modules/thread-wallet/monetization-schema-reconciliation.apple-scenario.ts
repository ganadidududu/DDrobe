import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import {
  countRows,
  invokeClientPurchase,
  invokeNotificationPurchase,
  postgresErrorSchema,
  type AppleNotificationDatabaseFixture,
  type ApplePurchaseDatabaseFixture
} from "./apple-app-store-notification.db-assertions";
import type { DisposableReconciliationDatabase } from "./monetization-schema-reconciliation.db-harness";

const purchaseFixture = (
  userId: string,
  transactionId: string
): ApplePurchaseDatabaseFixture => ({
  userId,
  transactionId,
  originalTransactionId: transactionId,
  productId: "com.inseong.coordit.thread.10",
  appAccountToken: userId,
  purchasedAt: "2026-08-21T00:00:00.000Z",
  environment: "Production",
  threadAmount: 10
});

const notificationFixture = (
  purchase: ApplePurchaseDatabaseFixture
): AppleNotificationDatabaseFixture => ({
  notificationUUID: randomUUID(),
  notificationType: "ONE_TIME_CHARGE",
  subtype: null,
  environment: purchase.environment,
  purchase
});

const expectInvalidAmount = async (
  database: DisposableReconciliationDatabase
): Promise<void> => {
  const userId = randomUUID();
  await database.client.query("insert into public.users(id) values ($1::uuid)", [userId]);
  const invalidPurchase = {
    ...purchaseFixture(userId, `reconcile-invalid-${randomUUID()}`),
    threadAmount: 20
  };
  const invalidNotification = notificationFixture(invalidPurchase);
  await assert.rejects(
    () => invokeNotificationPurchase(database.client, invalidNotification),
    (error: unknown) => {
      const parsed = postgresErrorSchema.safeParse(error);
      return parsed.success
        && parsed.data.code === "22023"
        && parsed.data.message === "apple_product_amount_invalid";
    }
  );
  assert.equal(await countRows(
    database.client,
    "select count(*) from public.thread_balances where user_id=$1::uuid",
    [userId]
  ), 0);
  assert.equal(await countRows(
    database.client,
    "select count(*) from public.thread_ledger_entries where user_id=$1::uuid",
    [userId]
  ), 0);
  assert.equal(await countRows(
    database.client,
    "select count(*) from public.apple_iap_transactions where transaction_id=$1::text",
    [invalidPurchase.transactionId]
  ), 0);
  assert.equal(await countRows(
    database.client,
    "select count(*) from public.apple_iap_notification_receipts where notification_uuid=$1::uuid",
    [invalidNotification.notificationUUID]
  ), 0);
};

export const assertReconciledAppleAtomicity = async (
  database: DisposableReconciliationDatabase
): Promise<void> => {
  const userId = randomUUID();
  await database.client.query("insert into public.users(id) values ($1::uuid)", [userId]);
  const purchase = purchaseFixture(userId, `reconcile-client-${randomUUID()}`);
  const notification = notificationFixture(purchase);

  assert.deepEqual(await invokeClientPurchase(database.client, purchase), {
    available_threads: 46,
    status: "credited"
  });
  assert.deepEqual(await invokeNotificationPurchase(database.client, notification), {
    available_threads: 46,
    status: "already_credited"
  });
  assert.deepEqual(await invokeNotificationPurchase(database.client, notification), {
    available_threads: 46,
    status: "already_processed"
  });
  assert.equal(await countRows(
    database.client,
    "select count(*) from public.thread_ledger_entries where user_id=$1::uuid and reason='iap_purchase'",
    [userId]
  ), 1);
  assert.equal(await countRows(
    database.client,
    "select count(*) from public.apple_iap_notification_receipts where notification_uuid=$1::uuid",
    [notification.notificationUUID]
  ), 1);

  const conflictingUserId = randomUUID();
  await database.client.query("insert into public.users(id) values ($1::uuid)", [conflictingUserId]);
  const conflictingPurchase = {
    ...purchase,
    userId: conflictingUserId,
    appAccountToken: conflictingUserId
  };
  await assert.rejects(
    () => invokeClientPurchase(database.client, conflictingPurchase),
    (error: unknown) => {
      const parsed = postgresErrorSchema.safeParse(error);
      return parsed.success
        && parsed.data.code === "23505"
        && parsed.data.message === "apple_transaction_metadata_conflict";
    }
  );
  assert.equal(await countRows(
    database.client,
    "select count(*) from public.thread_balances where user_id=$1::uuid",
    [conflictingUserId]
  ), 0);

  const raceUserId = randomUUID();
  await database.client.query("insert into public.users(id) values ($1::uuid)", [raceUserId]);
  const racePurchase = purchaseFixture(raceUserId, `reconcile-race-${randomUUID()}`);
  const raceNotification = notificationFixture(racePurchase);
  const clientConnection = await database.openClient();
  const notificationConnection = await database.openClient();
  const results = await Promise.all([
    invokeClientPurchase(clientConnection, racePurchase),
    invokeNotificationPurchase(notificationConnection, raceNotification)
  ]);
  assert.deepEqual(results.map((result) => result.status).sort(), ["already_credited", "credited"]);
  assert.deepEqual(results.map((result) => result.available_threads), [46, 46]);
  assert.equal(await countRows(
    database.client,
    "select count(*) from public.thread_ledger_entries where user_id=$1::uuid and reason='iap_purchase'",
    [raceUserId]
  ), 1);
  assert.equal(await countRows(
    database.client,
    "select count(*) from public.apple_iap_notification_receipts where notification_uuid=$1::uuid",
    [raceNotification.notificationUUID]
  ), 1);
  await expectInvalidAmount(database);
};
