import type { NextFunction, Response } from "express";
import { z } from "zod";
import { env } from "../../config/env";
import type { AuthenticatedRequest } from "../../shared/types/http";
import { createHttpError } from "../../shared/utils/http-error";
import { requireUser } from "../../shared/utils/request";
import {
  getThreadBalance,
  submitAppleIapPurchase,
  type AppleIapCreditResult,
  type AppleIapPurchaseRequest
} from "./thread-wallet.service";

const appleIapPurchaseRequestSchema = z.object({
  signedTransaction: z.string().trim().min(1)
});

type AppleIapPurchaseControllerDependencies = {
  readonly submitAppleIapPurchase: (request: AppleIapPurchaseRequest) => Promise<AppleIapCreditResult>;
};

const defaultAppleIapPurchaseControllerDependencies: AppleIapPurchaseControllerDependencies = {
  submitAppleIapPurchase
};

export const getThreadBalanceController = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    res.json({ availableThreads: await getThreadBalance(requireUser(req).id) });
  } catch (error) { // no-excuse-ok: catch -- Express forwards boundary errors centrally.
    next(error);
  }
};

export const getMonetizationReadinessController = (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): void => {
  try {
    requireUser(req);
    res.json({
      rewardedAdsEnabled: env.admobRewardedEnabled,
      iapEnabled: env.appleIapEnabled
    });
  } catch (error) { // no-excuse-ok: catch -- Express forwards boundary errors centrally.
    next(error);
  }
};

export const createAppleIapPurchaseController = (
  dependencies: AppleIapPurchaseControllerDependencies = defaultAppleIapPurchaseControllerDependencies
) => {
  return async (req: AuthenticatedRequest, res: Response, next: NextFunction): Promise<void> => {
    try {
      const parsed = appleIapPurchaseRequestSchema.safeParse(req.body);
      if (!parsed.success) throw createHttpError(400, "signedTransaction is required");
      const result = await dependencies.submitAppleIapPurchase({
        userId: requireUser(req).id,
        signedTransaction: parsed.data.signedTransaction
      });
      res.status(result.status === "credited" ? 201 : 200).json(result);
    } catch (error) { // no-excuse-ok: catch -- Express forwards boundary errors centrally.
      next(error);
    }
  };
};

export const appleIapPurchaseController = createAppleIapPurchaseController();
