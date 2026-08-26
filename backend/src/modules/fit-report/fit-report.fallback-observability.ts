export type FitReportFallbackCategory =
  | "not_configured"
  | "http_error"
  | "completion_invalid"
  | "report_invalid"
  | "narrative_rejected"
  | "timeout"
  | "unknown";

export class FitReportFallbackError extends Error {
  readonly name = "FitReportFallbackError";

  constructor(readonly category: FitReportFallbackCategory) {
    super(category);
  }
}

export const classifyFitReportFallback = (error: unknown): FitReportFallbackCategory => {
  if (error instanceof FitReportFallbackError) {
    return error.category;
  }
  if (error instanceof DOMException && error.name === "TimeoutError") {
    return "timeout";
  }
  return "unknown";
};

export const logFitReportFallback = (
  category: FitReportFallbackCategory,
  modelName: string
): void => {
  console.warn("fit_report_fallback", { category, modelName });
};
