import { env } from "../../config/env";
import { buildFitReportInput } from "./fit-report.builder";
import { buildFallbackFitReport } from "./fit-report.fallback";
import { buildFitReportPrompt, FIT_REPORT_PROMPT_VERSION } from "./fit-report.prompt";
import {
  hasAcceptedCoreNarrative,
  sanitizeGeneratedReport
} from "./fit-report.sanitizer";
import type {
  FitReportInput,
  FitReportJson,
  GenerateFitReportOptions,
  GenerateFitReportResult
} from "./fit-report.types";

interface OllamaGenerateResponse {
  response?: string;
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  Boolean(value) && typeof value === "object" && !Array.isArray(value);

const asStringArray = (value: unknown): string[] =>
  Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];

const normalizeReportJson = (value: unknown): FitReportJson => {
  if (!isRecord(value)) throw new Error("LLM report was not a JSON object");
  const measurementAnalysisValue = value.measurementAnalysis;
  const measurementAnalysis = Array.isArray(measurementAnalysisValue)
    ? measurementAnalysisValue.flatMap((item) => {
      if (!isRecord(item)) return [];
      const measurement = item.measurement;
      const text = item.text;
      if (typeof measurement !== "string" || typeof text !== "string") return [];
      return [{ measurement, text }];
    })
    : [];

  return {
    title: typeof value.title === "string" ? value.title : "핏 리포트",
    summary: typeof value.summary === "string" ? value.summary : "",
    recommendationReason: typeof value.recommendationReason === "string" ? value.recommendationReason : "",
    measurementAnalysis,
    cautions: asStringArray(value.cautions),
    nextActions: asStringArray(value.nextActions)
  };
};

const extractJsonObject = (text: string): FitReportJson => {
  try {
    return normalizeReportJson(JSON.parse(text));
  } catch {
    const start = text.indexOf("{");
    const end = text.lastIndexOf("}");
    if (start === -1 || end === -1 || end <= start) {
      throw new Error("LLM response did not contain JSON");
    }
    return normalizeReportJson(JSON.parse(text.slice(start, end + 1)));
  }
};

export { buildFallbackFitReport } from "./fit-report.fallback";

const callOllama = async (prompt: string, modelName: string): Promise<FitReportJson> => {
  const response = await fetch(env.ollamaGenerateUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: modelName,
      prompt,
      stream: false,
      think: false,
      options: {
        temperature: 0.2,
        top_p: 0.9
      }
    })
  });

  if (!response.ok) {
    throw new Error(`Ollama HTTP ${response.status}`);
  }

  const data = await response.json() as OllamaGenerateResponse;
  if (typeof data.response !== "string") {
    throw new Error("Ollama response was missing response text");
  }
  return extractJsonObject(data.response);
};

export const generateFitReport = async (
  userId: string,
  fitAnalysisResultId: string,
  options: GenerateFitReportOptions = {}
): Promise<GenerateFitReportResult> => {
  const reportInput = await buildFitReportInput(userId, fitAnalysisResultId, options);
  const prompt = buildFitReportPrompt(reportInput);
  const modelName = options.model ?? env.ollamaModel;

  try {
    const generatedReport = await callOllama(prompt, modelName);
    const fallbackReport = buildFallbackFitReport(reportInput);
    const report = sanitizeGeneratedReport(
      generatedReport,
      reportInput,
      fallbackReport
    );
    const coreNarrativeAccepted = hasAcceptedCoreNarrative(generatedReport, reportInput);
    return {
      fitAnalysisResultId,
      source: coreNarrativeAccepted ? "ollama" : "fallback",
      modelName,
      promptVersion: FIT_REPORT_PROMPT_VERSION,
      report: coreNarrativeAccepted ? report : fallbackReport,
      chartData: reportInput.chartData,
      ...(options.includeDebug ? { reportInput, prompt } : {})
    };
  } catch {
    return {
      fitAnalysisResultId,
      source: "fallback",
      modelName,
      promptVersion: FIT_REPORT_PROMPT_VERSION,
      report: buildFallbackFitReport(reportInput),
      chartData: reportInput.chartData,
      ...(options.includeDebug ? { reportInput, prompt } : {})
    };
  }
};
