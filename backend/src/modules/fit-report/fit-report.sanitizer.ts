import type { FitReportInput, FitReportJson } from "./fit-report.types";
import { buildMeasurementWearerImpact } from "./fit-report.garment-context";

const forbiddenNarrativePatterns = [
  /저신뢰도|신뢰도|confidence|피드백/i,
  /가중\s*(?:거리|오차|차이|점수|값)|가중치|weighted\s*(?:fit\s*)?distance|weightedFitDistance|정규화\s*(?:거리|오차)|내부\s*(?:계산\s*)?(?:거리|가중치|점수)/i,
  /(?:기준|참조|참고|비교)[^.!?\n]{0,20}(?:의류|옷|샘플|표본|데이터)[^.!?\n]{0,40}(?:부족|적(?:다|음|습니다|어요)?|한\s*벌(?:뿐|만)?|하나(?:뿐|만)?|소수|충분(?:하지|치)\s*않)/i,
  /(?:판단|분석|비교)\s*(?:근거|자료|데이터)[^.!?\n]{0,30}(?:부족|제한|적(?:다|음|습니다|어요)?|충분(?:하지|치)\s*않)/i,
  /(?:여름|겨울|봄|가을|한여름|환절기|장마)\s*(?:철|용|옷|코디|착용)?/i,
  /(?:린넨|울|캐시미어|가죽|기모|플리스|실크|벨벳|코듀로이|데님\s*(?:소재|원단)|면\s*(?:소재|원단)|코튼\s*(?:소재|원단)|폴리(?:에스터)?\s*(?:소재|원단)|나일론\s*(?:소재|원단))/i,
  /(?:포켓|주머니)(?:\s*(?:이|가|은|는|에|의|을|를|주변|디테일))?/i,
  /(?:두꺼운|얇은|가벼운|무거운)\s*(?:원단|소재|이너|아우터|옷)/i
] as const;

const hasForbiddenNarrative = (text: string): boolean =>
  forbiddenNarrativePatterns.some((pattern) => pattern.test(text));

const extractNumbers = (text: string): number[] =>
  [...text.matchAll(/[+-]?\d+(?:\.\d+)?/g)]
    .map((match) => Number(match[0]))
    .filter(Number.isFinite);

const collectReportNumbers = (reportInput: FitReportInput): number[] => [
  reportInput.recommendation.fitScore,
  ...(reportInput.recommendation.scoreGapToSecond === null
    ? []
    : [reportInput.recommendation.scoreGapToSecond]),
  ...reportInput.sizeScores.flatMap((size) => [
    size.fitScore,
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

const hasMeasurementUnit = (text: string): boolean => /[+-]?\d+(?:\.\d+)?\s*cm\b/i.test(text);

const assertNever = (value: never): never => {
  throw new Error(`Unsupported measurement key: ${value}`);
};

type NarrativeMinimumDetail = {
  readonly length: number;
  readonly sentences: number;
};

const isUsableNarrative = (
  text: string,
  reportInput: FitReportInput,
  minimumDetail: NarrativeMinimumDetail
): boolean =>
  hasMinimumDetail(text, minimumDetail.length, minimumDetail.sentences) &&
  !hasForbiddenNarrative(text) &&
  !hasMeasurementUnit(text) &&
  hasSupportedNumbers(text, reportInput);

const summaryMinimumDetail = { length: 80, sentences: 4 } as const;
const recommendationMinimumDetail = { length: 120, sentences: 6 } as const;

const topicParticle = (label: string): string => {
  const lastCharacter = label.at(-1);
  if (!lastCharacter) return "은";
  const hangulOffset = lastCharacter.charCodeAt(0) - 0xac00;
  return hangulOffset >= 0 && hangulOffset <= 11171 && hangulOffset % 28 !== 0 ? "은" : "는";
};

const measurementFitSentence = (row: FitReportInput["measurements"][number]): string => {
  switch (row.key) {
    case "total_length":
      return row.diff < 0
        ? "기준보다 짧아 밑단 위치가 평소보다 위로 올라갈 수 있습니다."
        : row.diff > 0
          ? "기준보다 길어 밑단 위치가 평소보다 아래로 내려갈 수 있습니다."
          : "기준과 같은 길이로 밑단 위치가 익숙한 기준에 가깝습니다.";
    case "sleeve_length":
      return row.diff < 0
        ? "기준보다 짧아 손목이 더 드러나는 방향입니다."
        : row.diff > 0
          ? "기준보다 길어 손목과 손등을 더 덮는 방향입니다."
          : "기준과 같은 길이로 손목을 덮는 정도가 익숙한 기준에 가깝습니다.";
    case "outseam":
      return row.diff < 0
        ? "기준보다 짧아 밑단이 발목 쪽에서 더 빨리 끝나는 방향입니다."
        : row.diff > 0
          ? "기준보다 길어 신발 위에서 밑단이 더 길게 머무는 방향입니다."
          : "기준과 같은 길이로 신발 위 밑단의 마무리가 익숙한 기준에 가깝습니다.";
    case "rise":
      return row.diff < 0
        ? "기준보다 짧아 허리선이 낮거나 몸에 더 가깝게 자리할 수 있습니다."
        : row.diff > 0
          ? "기준보다 길어 허리선이 높거나 여유 있게 자리할 수 있습니다."
          : "기준과 같은 깊이로 허리선 위치가 익숙한 기준에 가깝습니다.";
    case "shoulder_width":
    case "chest_width":
    case "waist_width":
    case "hip_width":
      return row.diff < 0
        ? "기준보다 작아 이 부위는 상대적으로 타이트하게 느껴질 수 있습니다."
        : row.diff > 0
          ? "기준보다 커 이 부위에는 상대적으로 여유가 생길 수 있습니다."
          : "기준과 같은 수치로 이 부위의 볼륨은 익숙한 핏에 가깝습니다.";
    default:
      return assertNever(row.key);
  }
};

const safeNarrativeSentences = (text: string, reportInput: FitReportInput): string[] =>
  text.split(/[.!?。]+/)
    .map((sentence) => sentence.trim())
    .filter((sentence) =>
      sentence.length >= 20 &&
      !hasForbiddenNarrative(sentence) &&
      !hasMeasurementUnit(sentence) &&
      hasSupportedNumbers(sentence, reportInput)
    );

const repairNarrative = (
  text: string,
  fallback: string,
  reportInput: FitReportInput,
  minimumDetail: NarrativeMinimumDetail
): string => {
  if (isUsableNarrative(text, reportInput, minimumDetail)) return text;

  const repairedSentences = safeNarrativeSentences(text, reportInput);
  for (const sentence of safeNarrativeSentences(fallback, reportInput)) {
    if (repairedSentences.length >= minimumDetail.sentences) break;
    if (!repairedSentences.includes(sentence)) repairedSentences.push(sentence);
  }
  const repaired = `${repairedSentences.join(". ")}.`;
  return hasMinimumDetail(repaired, minimumDetail.length, minimumDetail.sentences)
    ? repaired
    : fallback;
};

export const hasAcceptedCoreNarrative = (
  report: FitReportJson,
  reportInput: FitReportInput
): boolean =>
  safeNarrativeSentences(report.summary, reportInput).length > 0 &&
  safeNarrativeSentences(report.recommendationReason, reportInput).length > 0;

export const formatSigned = (value: number): string => `${value > 0 ? "+" : ""}${value}`;

export const buildMeasurementAnalysisText = (
  row: FitReportInput["measurements"][number],
  targetProduct: FitReportInput["targetProduct"]
): string =>
  `${row.label}${topicParticle(row.label)} 기준 ${row.ideal}cm와 상품 ${row.product}cm를 비교하면 ${formatSigned(row.diff)}cm 차이입니다. ` +
  `${measurementFitSentence(row)} ` +
  `${buildMeasurementWearerImpact(row, targetProduct)}`;

const hasConsistentMeasurementNumbers = (
  text: string,
  row: FitReportInput["measurements"][number]
): boolean => {
  const numericTokens = [...text.matchAll(/[+-]?\d+(?:\.\d+)?/g)].map((match) => match[0]);
  const numericValues = numericTokens.map(Number).filter(Number.isFinite);
  const allowedValues = [row.ideal, row.product, row.diff];
  const contains = (expected: number): boolean =>
    numericValues.some((value) => Math.abs(value - expected) < 0.001);
  const containsSignedDiff = numericTokens.some((value) => value === formatSigned(row.diff));

  return numericValues.every((value) =>
    allowedValues.some((allowed) => Math.abs(value - allowed) < 0.001)
  ) && contains(row.ideal) && contains(row.product) && containsSignedDiff;
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
        hasMinimumDetail(generated.text, 80, 3) &&
        hasConsistentMeasurementNumbers(generated.text, row)
        ? generated.text
        : buildMeasurementAnalysisText(row, reportInput.targetProduct)
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
    return safeItems.length > 0 ? safeItems.slice(0, 2) : fallbackItems;
  };
  const alignedReport = alignMeasurementAnalysis(report, reportInput);

  return {
    ...alignedReport,
    title: report.title.trim().length >= 4 &&
      !hasForbiddenNarrative(report.title) &&
      hasSupportedNumbers(report.title, reportInput)
      ? report.title
      : fallback.title,
    summary: repairNarrative(
      report.summary,
      fallback.summary,
      reportInput,
      summaryMinimumDetail
    ),
    recommendationReason: repairNarrative(
      report.recommendationReason,
      fallback.recommendationReason,
      reportInput,
      recommendationMinimumDetail
    ),
    cautions: sanitizeItems(report.cautions, fallback.cautions),
    nextActions: sanitizeItems(report.nextActions, fallback.nextActions)
  };
};
