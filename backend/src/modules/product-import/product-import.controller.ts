import type { NextFunction, Response } from "express";
import { ZodError } from "zod";
import type { AuthenticatedRequest } from "../../shared/types/http";
import { requireUser } from "../../shared/utils/request";
import { ProductImportError } from "./product-import.error";
import { productImportPreviewSchema, productImportRequestSchema } from "./product-import.schemas";
import { previewProductImport } from "./product-import.service";

export const previewProductImportController = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const request = productImportRequestSchema.parse(req.body);
    const preview = await previewProductImport(requireUser(req).id, request);
    res.json(productImportPreviewSchema.parse(preview));
  } catch (error) {
    if (error instanceof ProductImportError) {
      res.status(error.statusCode).json(error.toResponse());
      return;
    }
    if (error instanceof ZodError) {
      const invalid = new ProductImportError("INVALID_URL", "요청 형식 또는 URL이 올바르지 않습니다.", false, 400);
      res.status(invalid.statusCode).json(invalid.toResponse());
      return;
    }
    next(error);
  }
};
