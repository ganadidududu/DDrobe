import type { NextFunction, Response } from "express";
import type { AuthenticatedRequest } from "../../shared/types/http";
import { requireUser } from "../../shared/utils/request";
import { getThreadBalance } from "./thread-wallet.service";

export const getThreadBalanceController = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    res.json({ availableThreads: await getThreadBalance(requireUser(req).id) });
  } catch (error) {
    next(error);
  }
};
