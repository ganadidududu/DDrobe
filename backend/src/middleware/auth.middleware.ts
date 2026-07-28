import type { NextFunction, Response } from "express";
import { supabase } from "../config/supabase";
import type { AuthenticatedRequest, AuthUser } from "../shared/types/http";
import { createHttpError } from "../shared/utils/http-error";

type VerifyBearer = (token: string) => Promise<AuthUser | null>;

const verifySupabaseBearer: VerifyBearer = async (token) => {
  const { data } = await supabase.auth.getUser(token);
  if (!data.user) return null;
  return { id: data.user.id, email: data.user.email };
};

export const authenticateBearer = async (
  header: string | undefined,
  verifyBearer: VerifyBearer = verifySupabaseBearer
): Promise<AuthUser> => {
  if (!header?.startsWith("Bearer ")) {
    throw createHttpError(401, "Missing bearer token");
  }

  const user = await verifyBearer(header.slice("Bearer ".length));
  if (!user) {
    throw createHttpError(401, "로그인이 만료됐어요. 다시 로그인해 주세요.");
  }
  return user;
};

export const authMiddleware = async (
  req: AuthenticatedRequest,
  _res: Response,
  next: NextFunction
) => {
  try {
    req.user = await authenticateBearer(req.headers.authorization);
    return next();
  } catch (error) {
    return next(error instanceof Error ? error : createHttpError(401, "Unauthorized"));
  }
};
