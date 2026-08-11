import type { NextFunction, Response } from "express";
import type { AuthenticatedRequest } from "../../shared/types/http";
import { asOptionalString, asRequiredString, requireUser } from "../../shared/utils/request";
import { generateFitReport } from "./fit-report.service";
import type { ReportStyle } from "./fit-report.types";

const isReportStyle = (value: string | null): value is ReportStyle =>
  value === "concise_but_explanatory" || value === "detailed" || value === "short";

const isIdempotencyKey = (value: string | null): value is string =>
  value !== null && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);

export const generateFitReportController = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const style = asOptionalString(req.body.style);
    const idempotencyKey = asOptionalString(req.body.idempotencyKey);
    if (!isIdempotencyKey(idempotencyKey)) {
      res.status(400).json({ message: "A valid idempotencyKey is required" });
      return;
    }
    res.status(201).json(await generateFitReport(
      requireUser(req).id,
      asRequiredString(req.params.id, "fit analysis result id"),
      {
        idempotencyKey,
        selectedSizeLabel: asOptionalString(req.body.selectedSizeLabel) ?? undefined,
        style: isReportStyle(style) ? style : undefined,
        includeDebug: req.body.includeDebug === true
      }
    ));
  } catch (error) {
    next(error);
  }
};
