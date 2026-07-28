import type { FitReportInput, FitReportJson } from "./fit-report.types";

const forbiddenNarrativePattern =
  /저신뢰도|신뢰도|피드백|기준\s*(?:의류|옷|샘플)[^.!?\n]{0,40}(?:부족|적(?:다|음|습니다|어요)?)/i;

const hasForbiddenNarrative = (text: string): boolean => forbiddenNarrativePattern.test(text);

const extractNumbers = (text: string): number[] =>
  [...text.matchAll(/[+-]?\d+(?:\.\d+)?/g)]
    .map((match) => Number(match[0]))
    .filter(Number.isFinite);

const collectReportNumbers = (reportInput: FitReportInput): number[] => [
  reportInput.recommendation.fitScore,
  reportInput.recommendation.weightedFitDistance,
  ...(reportInput.recommendation.scoreGapToSecond === null
    ? []
    : [reportInput.recommendation.scoreGapToSecond]),
  ...reportInput.sizeScores.flatMap((size) => [
    size.fitScore,
    size.weightedFitDistance,
    ...extractNumbers(size.sizeLabel)
  ]),
  ...reportInput.measurements.flatMap((row) => [
    row.ideal,
    row.product,
    row.diff,
    Math.abs(row.diff)
  ]),
  ...extractNumbers(reportInput.recommendation.recommendedSize)
];

const hasSupportedNumbers = (text: string, reportInput: FitReportInput): boolean => {
  const allowedNumbers = collectReportNumbers(reportInput);
  return extractNumbers(text).every((value) =>
    allowedNumbers.some((allowed) => Math.abs(value - allowed) < 0.001)
  );
};

const hasMinimumDetail = (text: string, minimumLength: number, minimumSentences: number): boolean =>
  text.trim().length >= minimumLength &&
  text.split(/[.!?。]+/).filter((sentence) => sentence.trim().length > 0).length >= minimumSentences;

const isUsableNarrative = (
  text: string,
  reportInput: FitReportInput,
  minimumDetail: { readonly length: number; readonly sentences: number }
): boolean =>
  hasMinimumDetail(text, minimumDetail.length, minimumDetail.sentences) &&
  !hasForbiddenNarrative(text) &&
  hasSupportedNumbers(text, reportInput);

const summaryMinimumDetail = { length: 80, sentences: 3 } as const;
const recommendationMinimumDetail = { length: 120, sentences: 4 } as const;

export const formatSigned = (value: number): string => `${value > 0 ? "+" : ""}${value}`;

export const buildMeasurementAnalysisText = (
  row: FitReportInput["measurements"][number]
): string =>
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
  const numericValues = extractNumbers(text);
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
      text: generated &&
        !hasForbiddenNarrative(generated.text) &&
        hasConsistentMeasurementNumbers(generated.text, row)
        ? generated.text
        : buildMeasurementAnalysisText(row)
    };
  })
});

export const sanitizeGeneratedReport = (
  report: FitReportJson,
  reportInput: FitReportInput,
  fallback: FitReportJson
): FitReportJson => {
  const sanitizeItems = (items: string[], fallbackItems: string[]): string[] => {
    const safeItems = items.filter((item) =>
      item.trim().length >= 10 &&
      !hasForbiddenNarrative(item) &&
      hasSupportedNumbers(item, reportInput)
    );
    return safeItems.length > 0 ? safeItems : fallbackItems;
  };
  const alignedReport = alignMeasurementAnalysis(report, reportInput);

  return {
    ...alignedReport,
    title: report.title.trim().length >= 4 &&
      !hasForbiddenNarrative(report.title) &&
      hasSupportedNumbers(report.title, reportInput)
      ? report.title
      : fallback.title,
    summary: isUsableNarrative(report.summary, reportInput, summaryMinimumDetail)
      ? report.summary
      : fallback.summary,
    recommendationReason: isUsableNarrative(
      report.recommendationReason,
      reportInput,
      recommendationMinimumDetail
    )
      ? report.recommendationReason
      : fallback.recommendationReason,
    cautions: sanitizeItems(report.cautions, fallback.cautions),
    nextActions: sanitizeItems(report.nextActions, fallback.nextActions)
  };
};
