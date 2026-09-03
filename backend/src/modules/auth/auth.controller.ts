import type { NextFunction, Request, Response } from "express";
import { authenticateBearer } from "../../middleware/auth.middleware";
import { asRequiredString } from "../../shared/utils/request";
import {
  loginWithAppleIdToken,
  loginWithEmail,
  loginWithGoogleIdToken,
  signupWithEmail,
  type AuthResponse
} from "./auth.service";
import type { GuestUpgradeSession } from "./social-auth-upgrade.service";

type GoogleLoginControllerDependencies = {
  readonly loginWithGoogleIdToken: (
    idToken: string,
    guest: GuestUpgradeSession | null
  ) => Promise<AuthResponse>;
};

type AppleLoginControllerDependencies = {
  readonly loginWithAppleIdToken: (
    idToken: string,
    nonce: string,
    guest: GuestUpgradeSession | null
  ) => Promise<AuthResponse>;
};

const guestUpgradeSession = async (req: Request): Promise<GuestUpgradeSession | null> => {
  const refreshToken = req.body.guestRefreshToken;
  if (refreshToken === undefined && req.headers.authorization === undefined) return null;

  const parsedRefreshToken = asRequiredString(refreshToken, "guestRefreshToken");
  const user = await authenticateBearer(req.headers.authorization);
  const authorization = req.headers.authorization;
  if (!authorization?.startsWith("Bearer ")) return null;
  return {
    accessToken: authorization.slice("Bearer ".length),
    refreshToken: parsedRefreshToken,
    userId: user.id,
  };
};

export const signup = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const email = asRequiredString(req.body.email, "email");
    const password = asRequiredString(req.body.password, "password");
    res.status(201).json(await signupWithEmail(email, password));
  } catch (error) {
    next(error);
  }
};

export const login = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const email = asRequiredString(req.body.email, "email");
    const password = asRequiredString(req.body.password, "password");
    res.json(await loginWithEmail(email, password));
  } catch (error) {
    next(error);
  }
};

export const createGoogleLoginController = (
  dependencies: GoogleLoginControllerDependencies
) => async (req: Request, res: Response, next: NextFunction): Promise<void> => {
  try {
    const idToken = asRequiredString(req.body.idToken, "idToken");
    res.json(await dependencies.loginWithGoogleIdToken(idToken, await guestUpgradeSession(req)));
  } catch (error) {
    next(error);
  }
};

export const loginWithGoogle = createGoogleLoginController({ loginWithGoogleIdToken });

export const createAppleLoginController = (
  dependencies: AppleLoginControllerDependencies
) => async (req: Request, res: Response, next: NextFunction): Promise<void> => {
  try {
    const idToken = asRequiredString(req.body.idToken, "idToken");
    const nonce = asRequiredString(req.body.nonce, "nonce");
    res.json(await dependencies.loginWithAppleIdToken(
      idToken,
      nonce,
      await guestUpgradeSession(req)
    ));
  } catch (error) {
    next(error);
  }
};

export const loginWithApple = createAppleLoginController({ loginWithAppleIdToken });
