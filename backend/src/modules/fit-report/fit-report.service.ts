import { z } from "zod";
import { env } from "../../config/env";
import { consumeFitReportThread, getThreadBalance } from "../thread-wallet/thread-wallet.service";
import { buildFitReportInput } from "./fit-report.builder";
import { buildFallbackFitReport } from "./fit-report.fallback";
import { buildFitReportPrompt, FIT_REPORT_PROMPT_VERSION } from "./fit-report.prompt";
import { loadFitResult, loadPersistedFitReport, persistFitReport } from "./fit-report.repository";
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

const openRouterChatCompletionsUrl = "https://openrouter.ai/api/v1/chat/completions";

const fitReportJsonSchema = z.object({
  title: z.string(),
  summary: z.string(),
  recommendationReason: z.string(),
  measurementAnalysis: z.array(z.object({
    measurement: z.string(),
    text: z.string()
  })),
  cautions: z.array(z.string()),
  nextActions: z.array(z.string())
});

const openRouterCompletionSchema = z.object({
  choices: z.array(z.object({
    message: z.object({ content: z.string() })
  })).min(1)
});

const fitReportResponseFormat = {
  type: "json_schema",
  json_schema: {
    name: "fit_report",
    strict: true,
    schema: {
      type: "object",
      additionalProperties: false,
      required: [
        "title",
        "summary",
        "recommendationReason",
        "measurementAnalysis",
        "cautions",
        "nextActions"
      ],
      properties: {
        title: { type: "string" },
        summary: { type: "string" },
        recommendationReason: { type: "string" },
        measurementAnalysis: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: ["measurement", "text"],
            properties: {
              measurement: { type: "string" },
              text: { type: "string" }
            }
          }
        },
        cautions: {
          type: "array",
          items: { type: "string" },
          maxItems: 2
        },
        nextActions: {
          type: "array",
          items: { type: "string" },
          maxItems: 2
        }
      }
    }
  }
} as const;

class OpenRouterResponseError extends Error {
  readonly name = "OpenRouterResponseError";
}

export { buildFallbackFitReport } from "./fit-report.fallback";

const callOpenRouter = async (prompt: string, modelName: string): Promise<FitReportJson> => {
  if (!env.openRouterApiKey) {
    throw new OpenRouterResponseError("OpenRouter is not configured");
  }

  const response = await fetch(openRouterChatCompletionsUrl, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${env.openRouterApiKey}`,
      "Content-Type": "application/json"
    },
    signal: AbortSignal.timeout(env.openRouterTimeoutMs),
    body: JSON.stringify({
      model: modelName,
      stream: false,
      temperature: 0.2,
      messages: [{ role: "user", content: prompt }],
      response_format: fitReportResponseFormat,
      provider: {
        require_parameters: true,
        zdr: true,
        data_collection: "deny"
      }
    })
  });

  if (!response.ok) {
    throw new OpenRouterResponseError(`OpenRouter HTTP ${response.status}`);
  }

  const completion = openRouterCompletionSchema.parse(await response.json());
  const firstChoice = completion.choices[0];
  if (!firstChoice) {
    throw new OpenRouterResponseError("OpenRouter response was missing a choice");
  }
  return fitReportJsonSchema.parse(JSON.parse(firstChoice.message.content));
};

export const generateFitReport = async (
  userId: string,
  fitAnalysisResultId: string,
  options: GenerateFitReportOptions & { idempotencyKey: string }
): Promise<GenerateFitReportResult> => {
  if (!options.includeDebug) {
    const persisted = await loadPersistedFitReport(userId, fitAnalysisResultId);
    if (persisted) {
      return {
        ...persisted,
        availableThreads: await getThreadBalance(userId)
      };
    }
  }

  const reportInput = await buildFitReportInput(userId, fitAnalysisResultId, options);
  const prompt = buildFitReportPrompt(reportInput);
  const modelName = env.openRouterModel;
  const threadConsumption = await consumeFitReportThread(
    userId,
    options.idempotencyKey,
    fitAnalysisResultId
  );
  const fallbackReport = buildFallbackFitReport(reportInput);

  if (threadConsumption.status === "already_consumed") {
    if (!options.includeDebug) {
      const persisted = await loadPersistedFitReport(userId, fitAnalysisResultId);
      if (persisted) {
        return {
          ...persisted,
          availableThreads: threadConsumption.availableThreads
        };
      }
    }
    return {
      availableThreads: threadConsumption.availableThreads,
      fitAnalysisResultId,
      source: "fallback",
      modelName,
      promptVersion: FIT_REPORT_PROMPT_VERSION,
      report: fallbackReport,
      chartData: reportInput.chartData,
      ...(options.includeDebug ? { reportInput, prompt } : {})
    };
  }

  let generated: GenerateFitReportResult;
  try {
    const generatedReport = await callOpenRouter(prompt, modelName);
    const report = sanitizeGeneratedReport(
      generatedReport,
      reportInput,
      fallbackReport
    );
    const coreNarrativeAccepted = hasAcceptedCoreNarrative(generatedReport, reportInput);
    generated = {
      availableThreads: threadConsumption.availableThreads,
      fitAnalysisResultId,
      source: coreNarrativeAccepted ? "openrouter" : "fallback",
      modelName,
      promptVersion: FIT_REPORT_PROMPT_VERSION,
      report: coreNarrativeAccepted ? report : fallbackReport,
      chartData: reportInput.chartData,
      ...(options.includeDebug ? { reportInput, prompt } : {})
    };
  } catch {
    generated = {
      availableThreads: threadConsumption.availableThreads,
      fitAnalysisResultId,
      source: "fallback",
      modelName,
      promptVersion: FIT_REPORT_PROMPT_VERSION,
      report: fallbackReport,
      chartData: reportInput.chartData,
      ...(options.includeDebug ? { reportInput, prompt } : {})
    };
  }

  if (!options.includeDebug) {
    const fitResult = await loadFitResult(userId, fitAnalysisResultId);
    await persistFitReport(userId, fitResult, generated);
  }
  return generated;
};
