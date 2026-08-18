import type { NextFunction, Response } from "express";
import type { AuthenticatedRequest } from "../../shared/types/http";
import { requireUser } from "../../shared/utils/request";
import { isOnboardingCompleteForUser } from "./auth-onboarding-status.service";

export const getOnboardingStatus = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    res.json({ onboardingComplete: await isOnboardingCompleteForUser(requireUser(req).id) });
  } catch (error) {
    next(error);
  }
};
