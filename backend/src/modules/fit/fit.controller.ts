import type { NextFunction, Response } from "express";
import type { AuthenticatedRequest } from "../../shared/types/http";
import { asRequiredString, requireUser } from "../../shared/utils/request";
import {
  getFitAnalysisResult,
  listRecentFitAnalysisResults,
  prepareFitRecommendation,
  replayFitRecommendation
} from "./fit.service";
import { z } from "zod";
import {
  CLOSET_GARMENT_KINDS,
  getClosetReferenceProfile
} from "./reference-profile.service";
import {
  createFitAnalysisAndConsumeThread,
  findFitAnalysisThreadConsumption,
  getThreadBalance
} from "../thread-wallet/thread-wallet.service";

const closetGarmentKindSchema = z.enum(CLOSET_GARMENT_KINDS);

export const recommendFitController = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const user = requireUser(req);

    const { referenceClothingId, referenceClothingIds, externalProductId, idempotencyKey } = req.body as {
      referenceClothingId?: string;
      referenceClothingIds?: string[];
      externalProductId?: string;
      idempotencyKey?: string;
    };
    if (
      typeof idempotencyKey !== "string"
      || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(idempotencyKey)
    ) {
      res.status(400).json({ message: "A valid idempotencyKey is required" });
      return;
    }
    const existingResultID = await findFitAnalysisThreadConsumption(user.id, idempotencyKey);
    if (existingResultID) {
      res.status(200).json({
        ...replayFitRecommendation(await getFitAnalysisResult(user.id, existingResultID)),
        availableThreads: await getThreadBalance(user.id)
      });
      return;
    }
    const prepared = await prepareFitRecommendation({
      userId: user.id,
      referenceClothingId,
      referenceClothingIds,
      externalProductId: asRequiredString(externalProductId, "externalProductId")
    });

    const saved = await createFitAnalysisAndConsumeThread(
      user.id,
      idempotencyKey,
      prepared.persistence
    );
    if (saved.status === "insufficient") {
      res.status(402).json({ message: "실타래가 부족해요. 충전 후 다시 시도해 주세요." });
      return;
    }
    if (saved.status === "already_consumed") {
      if (!saved.fitAnalysisResultId) {
        throw new Error("Consumed analysis is missing its persisted result");
      }
      res.status(200).json({
        ...replayFitRecommendation(await getFitAnalysisResult(user.id, saved.fitAnalysisResultId)),
        availableThreads: saved.availableThreads
      });
      return;
    }
    if (!saved.fitAnalysisResultId) {
      throw new Error("Atomic fit analysis did not return a persisted result");
    }
    res.status(201).json({
      ...prepared.response,
      fitAnalysisResultId: saved.fitAnalysisResultId,
      availableThreads: saved.availableThreads
    });
  } catch (error) {
    next(error);
  }
};

export const recommendFitBatchController = async (
  _req: AuthenticatedRequest,
  res: Response,
  _next: NextFunction
) => {
  res.status(410).json({
    message: "Batch fit analysis is unavailable until every analysis can be charged atomically."
  });
};

export const recentFitAnalysisResultsController = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    res.json(await listRecentFitAnalysisResults(requireUser(req).id));
  } catch (error) {
    next(error);
  }
};

export const getFitAnalysisResultController = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    res.json(await getFitAnalysisResult(requireUser(req).id, asRequiredString(req.params.id, "id")));
  } catch (error) {
    next(error);
  }
};

export const getClosetReferenceProfileController = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const parsed = closetGarmentKindSchema.safeParse(req.params.garmentKind);
    if (!parsed.success) {
      res.status(400).json({ message: "garmentKind must be upper or lower" });
      return;
    }
    res.json(await getClosetReferenceProfile(requireUser(req).id, parsed.data));
  } catch (error) {
    next(error);
  }
};
