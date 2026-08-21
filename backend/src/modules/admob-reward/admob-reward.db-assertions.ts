import assert from "node:assert/strict";
import { z } from "zod";
import { withDatabaseRole } from "./admob-reward.db-harness";
import type { Client } from "pg";

export const uuidSchema = z.string().uuid();

const attemptRowSchema = z.object({
  id: uuidSchema,
  status: z.enum(["pending", "granted", "expired"]),
  expires_at: z.date()
});
const balanceRowSchema = z.object({ available_threads: z.number().int().nonnegative() });
const grantRowSchema = balanceRowSchema.extend({
  status: z.enum(["granted", "already_granted", "expired", "unknown_attempt"])
});
const consumptionRowSchema = balanceRowSchema.extend({
  status: z.enum(["consumed", "already_consumed", "insufficient"])
});
const postgresErrorSchema = z.object({ code: z.string(), message: z.string() });

export type GrantInvocation =
  | {
      readonly kind: "row";
      readonly httpStatus: 200 | 404 | 409;
      readonly status: z.infer<typeof grantRowSchema>["status"];
      readonly availableThreads: number;
    }
  | {
      readonly kind: "conflict";
      readonly httpStatus: 409;
      readonly category: "admob_transaction_attempt_conflict";
    };

const firstRow = <T>(rows: readonly T[]): T => {
  const row = rows[0];
  assert.notEqual(row, undefined);
  return row;
};

export const createAttempt = async (client: Client, userId: string): Promise<string> => {
  const result = await withDatabaseRole(client, "service_role", async (roleClient) => {
    return roleClient.query("select * from public.create_admob_reward_attempt($1::uuid)", [userId]);
  });
  return attemptRowSchema.parse(firstRow(result.rows)).id;
};

export const getBalance = async (client: Client, userId: string): Promise<number> => {
  const result = await withDatabaseRole(client, "service_role", async (roleClient) => {
    return roleClient.query("select * from public.get_thread_balance($1::uuid)", [userId]);
  });
  return balanceRowSchema.parse(firstRow(result.rows)).available_threads;
};

export const invokeGrant = async (
  client: Client,
  attemptId: string,
  transactionId: string
): Promise<GrantInvocation> => {
  try {
    const result = await withDatabaseRole(client, "service_role", async (roleClient) => {
      return roleClient.query("select * from public.grant_admob_reward($1::uuid, $2::text)", [
        attemptId,
        transactionId
      ]);
    });
    const row = grantRowSchema.parse(firstRow(result.rows));
    const httpStatus = row.status === "unknown_attempt" ? 404 : row.status === "expired" ? 409 : 200;
    return {
      kind: "row",
      httpStatus,
      status: row.status,
      availableThreads: row.available_threads
    };
  } catch (error) {
    const parsedError = postgresErrorSchema.safeParse(error);
    if (
      parsedError.success &&
      parsedError.data.code === "23505" &&
      parsedError.data.message === "admob_transaction_attempt_conflict"
    ) {
      return {
        kind: "conflict",
        httpStatus: 409,
        category: "admob_transaction_attempt_conflict"
      };
    }
    throw error;
  }
};

export const expectPermissionDenied = async (operation: () => Promise<unknown>): Promise<void> => {
  try {
    await operation();
    assert.fail("Expected database permission denial");
  } catch (error) {
    if (!(error instanceof Error)) {
      throw error;
    }
    const parsedError = postgresErrorSchema.safeParse(error);
    assert.equal(parsedError.success, true);
    if (parsedError.success) {
      assert.equal(parsedError.data.code, "42501");
    }
  }
};

export const countRows = async (
  client: Client,
  sql: string,
  values: readonly string[]
): Promise<number> => {
  const result = await client.query(sql, [...values]);
  return z.coerce.number().int().nonnegative().parse(firstRow(result.rows).count);
};

export const parseConsumptionRow = (
  rows: readonly Record<string, unknown>[]
): z.infer<typeof consumptionRowSchema> => {
  return consumptionRowSchema.parse(firstRow(rows));
};
