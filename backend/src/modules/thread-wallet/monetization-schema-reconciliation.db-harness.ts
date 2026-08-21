import {
  admobDatabaseMigrations,
  startDisposableAdmobDatabase,
  type DisposableAdmobDatabase
} from "../admob-reward/admob-reward.db-harness";
import { appleNotificationMigration } from "./apple-app-store-notification.db-harness";
import {
  applyMonetizationSchemaReconciliation,
  applyMonetizationSchemaReconciliationWithDisposableFailure,
  monetizationReconciliationApprovalToken,
  monetizationReconciliationFilename,
  type MonetizationReconciliationResult
} from "./monetization-schema-reconciliation.runner";

export const monetizationSchemaReconciliationMigration =
  monetizationReconciliationFilename;

export type ReconciliationBaseline = "fresh" | "production_partial";

export type ReconciliationPostflightMode = "verify" | "fail_after_migration";

export type ReconciliationApplyOptions = {
  readonly postflightMode?: ReconciliationPostflightMode;
};

export type DisposableReconciliationDatabase = DisposableAdmobDatabase & {
  readonly applyReconciliation: (
    options?: ReconciliationApplyOptions
  ) => Promise<MonetizationReconciliationResult>;
  readonly baseline: ReconciliationBaseline;
};

const productionPartialMigrations = [
  "20260730_add_thread_wallet.sql",
  "20260806_add_fit_report_thread_charge.sql",
  "20260811_add_admob_rewarded_ssv.sql"
] as const;

const freshMigrations = [...admobDatabaseMigrations, appleNotificationMigration] as const;

const normalizeObservedPartialReasonConstraint = async (
  database: DisposableAdmobDatabase
): Promise<void> => {
  await database.client.query(`
    alter table public.thread_ledger_entries
      drop constraint if exists thread_ledger_entries_reason_check;
    alter table public.thread_ledger_entries
      add constraint thread_ledger_entries_reason_check
      check (reason in ('fit_analysis', 'fit_report', 'iap_purchase', 'ad_reward', 'admin_adjustment'));
  `);
};

const assertNever = (value: never): never => {
  throw new TypeError(`Unexpected reconciliation postflight mode: ${String(value)}`);
};

export const startDisposableReconciliationDatabase = async (
  baseline: ReconciliationBaseline
): Promise<DisposableReconciliationDatabase> => {
  const migrationNames = baseline === "fresh" ? freshMigrations : productionPartialMigrations;
  const database = await startDisposableAdmobDatabase({ migrationNames });

  try {
    if (baseline === "production_partial") {
      await normalizeObservedPartialReasonConstraint(database);
    }
    return {
      ...database,
      baseline,
      applyReconciliation: async (options = {}) => {
        const postflightMode = options.postflightMode ?? "verify";
        switch (postflightMode) {
          case "verify":
            return applyMonetizationSchemaReconciliation(
              database.client,
              monetizationReconciliationApprovalToken
            );
          case "fail_after_migration":
            return applyMonetizationSchemaReconciliationWithDisposableFailure(
              database.client,
              monetizationReconciliationApprovalToken
            );
          default:
            return assertNever(postflightMode);
        }
      }
    };
  } catch (error) {
    await database.stop();
    throw error;
  }
};
