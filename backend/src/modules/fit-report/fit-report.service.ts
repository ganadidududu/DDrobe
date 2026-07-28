import { env } from "../../config/env";
import { buildFitReportInput } from "./fit-report.builder";
import { buildFitReportPrompt, FIT_REPORT_PROMPT_VERSION } from "./fit-report.prompt";
import {
  buildMeasurementAnalysisText,
  formatSigned,
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

const callOllama = async (prompt: string, modelName: string): Promise<FitReportJson> => {
  const response = await fetch(env.ollamaGenerateUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: modelName,
      prompt,
      stream: false,
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
    const coreNarrativeAccepted =
      report.summary === generatedReport.summary &&
      report.recommendationReason === generatedReport.recommendationReason;
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
