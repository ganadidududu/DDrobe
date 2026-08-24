import {
  startDisposableReconciliationDatabase,
  type DisposableReconciliationDatabase
} from "../thread-wallet/monetization-schema-reconciliation.db-harness";
import {
  applyProfileStylingSchemaReconciliation,
  applyProfileStylingSchemaReconciliationWithDisposableFailure,
  profileStylingReconciliationApprovalToken,
  type ProfileStylingReconciliationResult
} from "./profile-styling-schema-reconciliation.runner";

export type ProfileStylingPostflightMode = "verify" | "fail_after_migration";

export type ProfileStylingApplyOptions = {
  readonly postflightMode?: ProfileStylingPostflightMode;
};

export type DisposableProfileStylingDatabase = DisposableReconciliationDatabase & {
  readonly applyProfileStylingReconciliation: (
    options?: ProfileStylingApplyOptions
  ) => Promise<ProfileStylingReconciliationResult>;
  readonly profileStylingBaseline: "production_like_partial";
};

const assertNever = (value: never): never => {
  throw new TypeError(`Unexpected profile/styling postflight mode: ${String(value)}`);
};

export const startDisposableProfileStylingDatabase = async (): Promise<
  DisposableProfileStylingDatabase
> => {
  const database = await startDisposableReconciliationDatabase("production_partial");
  try {
    await database.applyReconciliation();
    return {
      ...database,
      profileStylingBaseline: "production_like_partial",
      applyProfileStylingReconciliation: async (options = {}) => {
        const postflightMode = options.postflightMode ?? "verify";
        switch (postflightMode) {
          case "verify":
            return applyProfileStylingSchemaReconciliation(
              database.client,
              profileStylingReconciliationApprovalToken
            );
          case "fail_after_migration":
            return applyProfileStylingSchemaReconciliationWithDisposableFailure(
              database.client,
              profileStylingReconciliationApprovalToken
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
