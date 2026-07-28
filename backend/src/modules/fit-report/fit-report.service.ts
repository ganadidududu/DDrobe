import { env } from "../../config/env";
import { createHttpError } from "../../shared/utils/http-error";
import { buildFitReportInput } from "./fit-report.builder";
import { buildFitReportPrompt, FIT_REPORT_PROMPT_VERSION } from "./fit-report.prompt";
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

const formatSigned = (value: number): string => `${value > 0 ? "+" : ""}${value}`;

const buildMeasurementAnalysisText = (row: FitReportInput["measurements"][number]): string =>
  `${row.label}은 기준 ${row.ideal}cm와 상품 ${row.product}cm를 비교하면 ${formatSigned(row.diff)}cm 차이입니다. ` +
  (row.diff < 0
    ? "기준보다 작아 이 부위는 상대적으로 타이트하게 느껴질 수 있습니다."
    : row.diff > 0
      ? "기준보다 커 이 부위에는 상대적으로 여유가 생길 수 있습니다."
      : "기준과 같은 수치로, 이 부위의 볼륨과 길이는 익숙한 핏에 가깝습니다.");

const hasConsistentMeasurementNumbers = (
  text: string,
  row: FitReportInput["measurements"][number]
): boolean => {
  const numericValues = [...text.matchAll(/[+-]?\d+(?:\.\d+)?/g)]
    .map((match) => Number(match[0]))
    .filter(Number.isFinite);
  const allowedValues = [row.ideal, row.product, row.diff, Math.abs(row.diff)];
  const contains = (expected: number): boolean =>
    numericValues.some((value) => Math.abs(value - expected) < 0.001);

  return numericValues.every((value) =>
    allowedValues.some((allowed) => Math.abs(value - allowed) < 0.001)
  ) && contains(row.ideal) && contains(row.product) && contains(Math.abs(row.diff));
};

const alignMeasurementAnalysis = (
  report: FitReportJson,
  reportInput: FitReportInput
): FitReportJson => ({
  ...report,
  measurementAnalysis: reportInput.measurements.map((row) => {
    const generated = report.measurementAnalysis.find((item) =>
      item.measurement === row.label || item.measurement === row.key
    );
    return {
      measurement: row.label,
      text: generated && hasConsistentMeasurementNumbers(generated.text, row)
        ? generated.text
        : buildMeasurementAnalysisText(row)
    };
  })
});

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
      `한 부위만 맞추는 대신 폭과 길이의 균형을 함께 맞춘 선택이라는 점이 추천의 핵심입니다.`,
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
    const report = alignMeasurementAnalysis(await callOllama(prompt, modelName), reportInput);
    return {
      fitAnalysisResultId,
      source: "ollama",
      modelName,
      promptVersion: FIT_REPORT_PROMPT_VERSION,
      report,
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
