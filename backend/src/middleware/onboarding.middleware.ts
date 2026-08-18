import type { NextFunction, Response } from "express";
import { isOnboardingCompleteForUser } from "../modules/auth/auth-onboarding-status.service";
import type { AuthenticatedRequest } from "../shared/types/http";
import { createHttpError } from "../shared/utils/http-error";

export const onboardingMiddleware = async (
  req: AuthenticatedRequest,
  _res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    if (!req.user || !(await isOnboardingCompleteForUser(req.user.id))) {
      throw createHttpError(403, "온보딩을 완료한 뒤 서비스를 이용할 수 있어요.");
    }
    next();
  } catch (error) {
    next(error);
  }
};
