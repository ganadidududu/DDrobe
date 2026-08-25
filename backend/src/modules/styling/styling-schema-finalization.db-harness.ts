import {
  startDisposableReconciliationDatabase,
  type DisposableReconciliationDatabase
} from "../thread-wallet/monetization-schema-reconciliation.db-harness";
import {
  applyStylingSchemaFinalization,
  applyStylingSchemaFinalizationWithDisposableFailure,
  stylingSchemaFinalizationApprovalToken,
  type StylingSchemaFinalizationResult
} from "./styling-schema-finalization.runner";

export type StylingFinalizationPostflightMode = "verify" | "fail_after_migration";

export type StylingFinalizationApplyOptions = {
  readonly postflightMode?: StylingFinalizationPostflightMode;
};

export type DisposableStylingFinalizationDatabase = DisposableReconciliationDatabase & {
  readonly applyStylingFinalization: (
    options?: StylingFinalizationApplyOptions
  ) => Promise<StylingSchemaFinalizationResult>;
  readonly stylingBaseline: "observed_live";
};

const assertNever = (value: never): never => {
  throw new TypeError(`Unexpected styling finalization postflight mode: ${String(value)}`);
};

export const startDisposableStylingFinalizationDatabase = async (): Promise<
  DisposableStylingFinalizationDatabase
> => {
  const database = await startDisposableReconciliationDatabase("production_partial");
  try {
    await database.applyReconciliation();
    await database.client.query("alter table public.users add column birth_date date");
    return {
      ...database,
      stylingBaseline: "observed_live",
      applyStylingFinalization: async (options = {}) => {
        const postflightMode = options.postflightMode ?? "verify";
        switch (postflightMode) {
          case "verify":
            return applyStylingSchemaFinalization(
              database.client,
              stylingSchemaFinalizationApprovalToken
            );
          case "fail_after_migration":
            return applyStylingSchemaFinalizationWithDisposableFailure(
              database.client,
              stylingSchemaFinalizationApprovalToken
            );
          default:
            return assertNever(postflightMode);
        }
      }
    };
  } catch (error: unknown) {
    await database.stop();
    throw error;
  }
};
