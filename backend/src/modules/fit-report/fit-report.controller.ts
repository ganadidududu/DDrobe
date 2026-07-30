import type { NextFunction, Response } from "express";
import type { AuthenticatedRequest } from "../../shared/types/http";
import { asOptionalString, asRequiredString, requireUser } from "../../shared/utils/request";
import { generateFitReport } from "./fit-report.service";
import type { ReportStyle } from "./fit-report.types";

const isReportStyle = (value: string | null): value is ReportStyle =>
  value === "concise_but_explanatory" || value === "detailed" || value === "short";

export const generateFitReportController = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const style = asOptionalString(req.body.style);
    res.status(201).json(await generateFitReport(
      requireUser(req).id,
      asRequiredString(req.params.id, "fit analysis result id"),
      {
        selectedSizeLabel: asOptionalString(req.body.selectedSizeLabel) ?? undefined,
        style: isReportStyle(style) ? style : undefined,
        includeDebug: req.body.includeDebug === true
      }
    ));
  } catch (error) {
    next(error);
  }
};
