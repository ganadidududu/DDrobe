import type { NextFunction, Request, Response } from "express";
import { z } from "zod";
import { createHttpError } from "../../shared/utils/http-error";
import {
  submitAppleAppStoreNotification,
  type AppleAppStoreNotificationRequest,
  type AppleAppStoreNotificationResult
} from "./apple-app-store-notification.service";

const appleNotificationRequestSchema = z.object({
  signedPayload: z.string().trim().min(1)
});

type AppleNotificationControllerDependencies = {
  readonly submitAppleAppStoreNotification: (
    request: AppleAppStoreNotificationRequest
  ) => Promise<AppleAppStoreNotificationResult>;
};

const defaultDependencies: AppleNotificationControllerDependencies = {
  submitAppleAppStoreNotification
};

export const createAppleAppStoreNotificationController = (
  dependencies: AppleNotificationControllerDependencies = defaultDependencies
) => {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const parsed = appleNotificationRequestSchema.safeParse(req.body);
      if (!parsed.success) throw createHttpError(400, "signedPayload is required");
      const result = await dependencies.submitAppleAppStoreNotification({
        signedPayload: parsed.data.signedPayload
      });
      if (result.kind === "record") {
        res.status(200).json({ status: result.status });
        return;
      }
      res.status(200).json({
        availableThreads: result.availableThreads,
        status: result.status
      });
    } catch (error) { // no-excuse-ok: catch -- Express forwards boundary errors centrally.
      next(error);
    }
  };
};

export const appleAppStoreNotificationController =
  createAppleAppStoreNotificationController();
