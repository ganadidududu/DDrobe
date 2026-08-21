import type { NextFunction, RequestHandler, Response } from "express";
import { env } from "../../config/env";
import type { AuthenticatedRequest } from "../../shared/types/http";
import { requireUser } from "../../shared/utils/request";
import { getGoogleVerifierKeys } from "./admob-reward.keys";
import { createRewardAttempt, getRewardAttempt, grantRewardForVerifiedCallback } from "./admob-reward.service";
import {
  AdMobSSVError,
  verifyAdMobSSVCallback,
  type AdMobSSVConfiguration,
  type AdMobSSVRejectionCategory,
  type VerifierKey
} from "./admob-reward.ssv";

type RewardSettlement = Awaited<ReturnType<typeof grantRewardForVerifiedCallback>>;

type RewardedSSVControllerDependencies = {
  readonly getVerifierKeys: () => Promise<readonly VerifierKey[]>;
  readonly grantReward: (attemptId: string, transactionId: string) => Promise<RewardSettlement>;
  readonly now: () => number;
  readonly configuration: AdMobSSVConfiguration;
  readonly logRejection: (category: AdMobSSVRejectionCategory) => void;
};

const assertNever = (_value: never): never => {
  throw new AdMobSSVError("malformed-callback", 500);
};

const logRejection = (category: AdMobSSVRejectionCategory): void => {
  console.warn("AdMob SSV callback rejected", { category });
};

export const createReceiveRewardedSSVController = (
  dependencies: RewardedSSVControllerDependencies
): RequestHandler => {
  return async (req, res, next) => {
    try {
      const callback = await verifyAdMobSSVCallback(req.originalUrl, dependencies);
      switch (callback.kind) {
        case "validation":
          res.status(200).json({ status: "validation" });
          return;
        case "reward":
          res.status(200).json(await dependencies.grantReward(
            callback.attemptId,
            callback.transactionId
          ));
          return;
        default:
          return assertNever(callback);
      }
    } catch (error) { // no-excuse-ok: catch
      if (error instanceof AdMobSSVError) {
        dependencies.logRejection(error.category);
      }
      next(error);
    }
  };
};

export const createRewardAttemptController = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    res.status(201).json(await createRewardAttempt(requireUser(req).id));
  } catch (error) { // no-excuse-ok: catch
    next(error);
  }
};
export const getRewardAttemptController = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    res.json(await getRewardAttempt(requireUser(req).id, req.params.id));
  } catch (error) { // no-excuse-ok: catch
    next(error);
  }
};
// Google authenticates this public route with its SSV signature.
export const receiveRewardedSSVController = createReceiveRewardedSSVController({
  getVerifierKeys: getGoogleVerifierKeys,
  grantReward: grantRewardForVerifiedCallback,
  now: Date.now,
  configuration: {
    rewardedAdsEnabled: env.admobRewardedEnabled,
    adUnitId: env.admobRewardedAdUnitId,
    rewardItem: env.admobRewardItem,
    rewardAmount: env.admobRewardAmount,
    validationCustomData: env.admobSsvValidationCustomData
  },
  logRejection
});
