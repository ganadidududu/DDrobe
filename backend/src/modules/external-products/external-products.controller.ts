import type { NextFunction, Response } from "express";
import { z } from "zod";
import type { AuthenticatedRequest } from "../../shared/types/http";
import { createHttpError } from "../../shared/utils/http-error";
import { asRequiredString, requireUser, sendCreated } from "../../shared/utils/request";
import {
  createExternalProductForUser,
  getExternalProductForUser,
  listExternalProductsForUser,
  updateExternalProductForUser
} from "./external-products.service";
import {
  FIT_LAB_CATEGORIES,
  toFitLabUrlPrefill
} from "../product-import/fit-lab-prefill.mapper";
import { previewProductImport } from "../product-import/product-import.service";

const fitLabUrlImportSchema = z.object({
  url: z.string().trim().min(1),
  category: z.enum(FIT_LAB_CATEGORIES).optional()
});

export const createExternalProduct = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    sendCreated(res, await createExternalProductForUser(requireUser(req).id, req.body));
  } catch (error) { // no-excuse-ok: catch — Express boundary forwards to shared middleware.
    next(error);
  }
};

export const listExternalProducts = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    res.json(await listExternalProductsForUser(requireUser(req).id));
  } catch (error) { // no-excuse-ok: catch — Express boundary forwards to shared middleware.
    next(error);
  }
};

export const getExternalProduct = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    res.json(await getExternalProductForUser(requireUser(req).id, asRequiredString(req.params.id, "id")));
  } catch (error) { // no-excuse-ok: catch — Express boundary forwards to shared middleware.
    next(error);
  }
};

export const updateExternalProduct = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    res.json(await updateExternalProductForUser(requireUser(req).id, asRequiredString(req.params.id, "id"), req.body));
  } catch (error) { // no-excuse-ok: catch — Express boundary forwards to shared middleware.
    next(error);
  }
};

export const createExternalProductFromUrl = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const parsed = fitLabUrlImportSchema.safeParse(req.body);
    if (!parsed.success) {
      throw createHttpError(400, "상품 링크와 카테고리를 확인해 주세요.");
    }
    const preview = await previewProductImport(requireUser(req).id, {
      url: parsed.data.url,
      includeImages: true,
      includeDetailImages: false
    });
    res.json(toFitLabUrlPrefill(preview, parsed.data.category));
  } catch (error) { // no-excuse-ok: catch — Express boundary forwards to shared middleware.
    next(error);
  }
};
