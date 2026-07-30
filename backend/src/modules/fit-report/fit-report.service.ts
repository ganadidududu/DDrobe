import { z } from "zod";
import { env } from "../../config/env";
import { buildFitReportInput } from "./fit-report.builder";
import { buildFitReportPrompt, FIT_REPORT_PROMPT_VERSION } from "./fit-report.prompt";
import {
  buildMeasurementAnalysisText,
  formatSigned,
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

const formatTopExplanationFactors = (reportInput: FitReportInput): string => {
  const factors = reportInput.explanation.topExplanationFactors.map((factor) =>
    `${factor.label} ${formatSigned(factor.diff)}cm`
  );
  return factors.length > 0 ? factors.join(", ") : "부위별 균형";
};

export const buildFallbackFitReport = (reportInput: FitReportInput): FitReportJson => {
  const topExplanationFactors = formatTopExplanationFactors(reportInput);
  const competingSizes = reportInput.sizeScores
    .filter((size) => size.sizeLabel !== reportInput.recommendation.recommendedSize)
    .map((size) => `${size.sizeLabel} ${size.fitScore}점`)
    .join(", ");
  return {
    title: `${reportInput.recommendation.recommendedSize} 사이즈 정밀 핏 리포트`,
    summary:
      `${reportInput.recommendation.recommendedSize} 사이즈의 핏 스코어는 ${reportInput.recommendation.fitScore}점으로 가장 높은 균형을 보입니다. ` +
      `기준 의류에서 만들어진 부위별 베스트 수치와 상품 실측을 함께 비교한 결과입니다. ` +
      `폭과 길이에서 생기는 차이를 나누어 보면 추천 사이즈의 실루엣과 타협점을 더 분명하게 이해할 수 있습니다. ` +
      `아래에서 각 부위의 차이와 다른 사이즈의 점수를 함께 확인하면 예상 실루엣을 더 구체적으로 판단할 수 있습니다.`,
    recommendationReason:
      `${reportInput.recommendation.recommendedSize} 사이즈는 비교 가능한 모든 부위를 종합했을 때 기준 수치에 가장 균형 있게 가까운 후보입니다.` +
      (competingSizes.length > 0
        ? ` 다른 후보 점수는 ${competingSizes}이며, 추천 사이즈가 전체 점수에서 앞섭니다.`
        : "") +
      (reportInput.recommendation.scoreGapToSecond !== null
        ? ` 두 번째 후보와의 점수 차이는 ${reportInput.recommendation.scoreGapToSecond}점입니다.`
        : "") +
      ` 특히 ${topExplanationFactors}가 사이즈 선택을 가르는 핵심 차이였습니다. ` +
      `폭 계열은 상체나 하체의 볼륨과 움직임 여유를 판단하는 기준으로 함께 살펴봤습니다. ` +
      `길이 계열은 익숙한 비율과 비교했을 때 어느 부분이 달라지는지 중심으로 확인했습니다. ` +
      `한 부위만 맞추는 대신 폭과 길이의 균형을 함께 맞춘 선택이라는 점이 추천의 핵심입니다. ` +
      `따라서 아래 부위별 차이가 평소 선호와 맞는지 확인한 뒤 이 사이즈를 선택하는 것을 권합니다.`,
    measurementAnalysis: reportInput.measurements.map((row) => ({
      measurement: row.label,
      text: buildMeasurementAnalysisText(row)
    })),
    cautions: ["소재의 신축성과 두께에 따라 같은 실측이라도 실제 착용감은 달라질 수 있습니다."],
    nextActions: [
      "차이가 가장 큰 부위가 평소 선호하는 실루엣과 맞는지 확인하세요.",
      "레이어드 착용 예정이라면 가슴·허리처럼 둘레에 영향을 주는 단면 수치를 우선 확인하세요."
    ]
  };
};

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
  options: GenerateFitReportOptions = {}
): Promise<GenerateFitReportResult> => {
  const reportInput = await buildFitReportInput(userId, fitAnalysisResultId, options);
  const prompt = buildFitReportPrompt(reportInput);
  const modelName = env.openRouterModel;

  try {
    const generatedReport = await callOpenRouter(prompt, modelName);
    const fallbackReport = buildFallbackFitReport(reportInput);
    const report = sanitizeGeneratedReport(
      generatedReport,
      reportInput,
      fallbackReport
    );
    const coreNarrativeAccepted = hasAcceptedCoreNarrative(generatedReport, reportInput);
    return {
      fitAnalysisResultId,
      source: coreNarrativeAccepted ? "openrouter" : "fallback",
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
