import type { NextFunction, Request, Response } from "express";
import { asRequiredString } from "../../shared/utils/request";
import {
  refreshAuthSession,
  type AuthRefreshResponse,
} from "./auth-refresh.service";

type RefreshControllerDependencies = {
  readonly refreshAuthSession: (refreshToken: string) => Promise<AuthRefreshResponse>;
};

export const createRefreshController = (
  dependencies: RefreshControllerDependencies
) => async (req: Request, res: Response, next: NextFunction): Promise<void> => {
  try {
    const refreshToken = asRequiredString(req.body.refreshToken, "refreshToken");
    res.json(await dependencies.refreshAuthSession(refreshToken));
  } catch (error) {
    next(error);
  }
};

export const refreshSessionController = createRefreshController({ refreshAuthSession });
