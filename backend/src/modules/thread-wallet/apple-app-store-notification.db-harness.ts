import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import {
  startDisposableAdmobDatabase,
  type DisposableAdmobDatabase
} from "../admob-reward/admob-reward.db-harness";

export const appleNotificationMigration =
  "20260821_add_apple_iap_notification_receipts.sql" as const;

export type DisposableAppleNotificationDatabase = DisposableAdmobDatabase & {
  readonly appleNotificationMigration: typeof appleNotificationMigration;
};

export const startDisposableAppleNotificationDatabase = async (
): Promise<DisposableAppleNotificationDatabase> => {
  const database = await startDisposableAdmobDatabase();
  try {
    const migrationPath = resolve(
      process.cwd(),
      "..",
      "supabase",
      "migrations",
      appleNotificationMigration
    );
    await database.client.query(await readFile(migrationPath, "utf8"));
    return {
      ...database,
      appleNotificationMigration
    };
  } catch (error) {
    await database.stop();
    throw error;
  }
};
