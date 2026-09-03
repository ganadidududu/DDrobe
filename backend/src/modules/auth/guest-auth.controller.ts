import type { NextFunction, Request, Response } from "express";
import { asRequiredString, requireUser } from "../../shared/utils/request";
import { appleDeviceWelcomeRegistry } from "./apple-device-check";
import {
  claimGuestWelcome,
  createGuestSession,
  type GuestSessionRepository,
  type GuestWelcomeResult,
} from "./guest-auth.service";
import {
  guestSessionRepository,
  guestWelcomeRepository,
} from "./guest-auth.repository";

type GuestSessionControllerDependencies = {
  readonly repository: GuestSessionRepository;
};

type GuestWelcomeControllerDependencies = {
  readonly claimWelcome: (userId: string, deviceToken: string) => Promise<GuestWelcomeResult>;
};

export const createGuestSessionController = (
  dependencies: GuestSessionControllerDependencies
) => async (_req: Request, res: Response, next: NextFunction): Promise<void> => {
  try {
    res.status(201).json(await createGuestSession(dependencies.repository));
  } catch (error) {
    next(error);
  }
};

export const createGuestWelcomeController = (
  dependencies: GuestWelcomeControllerDependencies
) => async (req: Request, res: Response, next: NextFunction): Promise<void> => {
  try {
    const user = requireUser(req);
    const deviceToken = asRequiredString(req.body.deviceToken, "deviceToken");
    res.json(await dependencies.claimWelcome(user.id, deviceToken));
  } catch (error) {
    next(error);
  }
};

export const guestSessionController = createGuestSessionController({
  repository: guestSessionRepository,
});

export const guestWelcomeController = createGuestWelcomeController({
  claimWelcome: async (userId, deviceToken) =>
    claimGuestWelcome(userId, deviceToken, {
      repository: guestWelcomeRepository,
      deviceRegistry: appleDeviceWelcomeRegistry,
    }),
});
