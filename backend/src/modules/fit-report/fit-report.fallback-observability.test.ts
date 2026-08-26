import assert from "node:assert/strict";
import {
  FitReportFallbackError,
  classifyFitReportFallback,
  logFitReportFallback
} from "./fit-report.fallback-observability";

const main = (): void => {
  assert.equal(
    classifyFitReportFallback(new FitReportFallbackError("report_invalid")),
    "report_invalid"
  );
  assert.equal(
    classifyFitReportFallback(new DOMException("timed out", "TimeoutError")),
    "timeout"
  );
  assert.equal(classifyFitReportFallback(new Error("sensitive provider response")), "unknown");

  const warnings: unknown[][] = [];
  const originalWarn = console.warn;
  console.warn = (...values: unknown[]): void => {
    warnings.push(values);
  };
  try {
    logFitReportFallback("narrative_rejected", "google/gemini-2.5-flash");
  } finally {
    console.warn = originalWarn;
  }

  assert.deepEqual(warnings, [[
    "fit_report_fallback",
    {
      category: "narrative_rejected",
      modelName: "google/gemini-2.5-flash"
    }
  ]]);
  assert.equal(JSON.stringify(warnings).includes("sensitive provider response"), false);
};

main();
