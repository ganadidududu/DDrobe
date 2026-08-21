import assert from "node:assert/strict";
import { z } from "zod";
import { withDatabaseRole } from "../admob-reward/admob-reward.db-harness";
import type { Client } from "pg";

const settlementRowSchema = z.object({
  available_threads: z.number().int().nonnegative(),
  status: z.enum(["credited", "already_credited", "already_processed"])
});
const recordRowSchema = z.object({
  status: z.enum(["processed", "already_processed"])
});
const countRowSchema = z.object({ count: z.coerce.number().int().nonnegative() });
export const postgresErrorSchema = z.object({ code: z.string(), message: z.string() });

export type ApplePurchaseDatabaseFixture = {
  readonly userId: string;
  readonly transactionId: string;
  readonly originalTransactionId: string;
  readonly productId: string;
  readonly appAccountToken: string;
  readonly purchasedAt: string;
  readonly environment: "Sandbox" | "Production";
  readonly threadAmount: number;
};

export type AppleNotificationDatabaseFixture = {
  readonly notificationUUID: string;
  readonly notificationType: "ONE_TIME_CHARGE";
  readonly subtype: string | null;
  readonly environment: "Sandbox" | "Production";
  readonly purchase: ApplePurchaseDatabaseFixture;
};

const firstRow = <T>(rows: readonly T[]): T => {
  const row = rows[0];
  assert.notEqual(row, undefined);
  return row;
};

export const invokeClientPurchase = async (
  client: Client,
  purchase: ApplePurchaseDatabaseFixture
): Promise<z.infer<typeof settlementRowSchema>> => {
  const result = await withDatabaseRole(client, "service_role", async (roleClient) => {
    return roleClient.query(
      "select * from public.grant_apple_iap_threads($1::uuid,$2::text,$3::text,$4::text,$5::uuid,$6::timestamptz,$7::text,$8::integer)",
      [
        purchase.userId,
        purchase.transactionId,
        purchase.originalTransactionId,
        purchase.productId,
        purchase.appAccountToken,
        purchase.purchasedAt,
        purchase.environment,
        purchase.threadAmount
      ]
    );
  });
  return settlementRowSchema.parse(firstRow(result.rows));
};

export const invokeNotificationPurchase = async (
  client: Client,
  notification: AppleNotificationDatabaseFixture
): Promise<z.infer<typeof settlementRowSchema>> => {
  const purchase = notification.purchase;
  const result = await withDatabaseRole(client, "service_role", async (roleClient) => {
    return roleClient.query(
      "select * from public.reconcile_apple_iap_notification($1::uuid,$2::text,$3::text,$4::text,$5::uuid,$6::text,$7::text,$8::text,$9::uuid,$10::timestamptz,$11::text,$12::integer)",
      [
        notification.notificationUUID,
        notification.notificationType,
        notification.subtype,
        notification.environment,
        purchase.userId,
        purchase.transactionId,
        purchase.originalTransactionId,
        purchase.productId,
        purchase.appAccountToken,
        purchase.purchasedAt,
        purchase.environment,
        purchase.threadAmount
      ]
    );
  });
  return settlementRowSchema.parse(firstRow(result.rows));
};

export const invokeRecordOnlyNotification = async (
  client: Client,
  notificationUUID: string,
  environment: "Sandbox" | "Production"
): Promise<z.infer<typeof recordRowSchema>> => {
  const result = await withDatabaseRole(client, "service_role", async (roleClient) => {
    return roleClient.query(
      "select * from public.record_apple_iap_notification($1::uuid,$2::text,$3::text,$4::text)",
      [notificationUUID, "TEST", null, environment]
    );
  });
  return recordRowSchema.parse(firstRow(result.rows));
};

export const countRows = async (
  client: Client,
  sql: string,
  values: readonly string[]
): Promise<number> => {
  const result = await client.query(sql, [...values]);
  return countRowSchema.parse(firstRow(result.rows)).count;
};
