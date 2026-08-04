import type { MeasurementKey } from "../../shared/types/database";
import type { FitReportInput, FitReportJson, MeasurementReportRow, SizeFitOption } from "./fit-report.types";

const lengthMeasurementKeys: readonly MeasurementKey[] = [
  "total_length",
  "sleeve_length",
  "rise",
  "outseam"
] as const;

const statusPriority: Readonly<Record<string, number>> = {
  too_tight: 4,
  too_loose: 4,
  tight: 3,
  loose: 3,
  good: 1
};

const formatNumber = (value: number): string => `${value}`;

const isLengthMeasurement = (key: MeasurementKey): boolean =>
  lengthMeasurementKeys.includes(key);

const isBalanced = (measurements: readonly MeasurementReportRow[]): boolean =>
  measurements.length > 0 && measurements.every((measurement) => measurement.status === "good");

const mostNoticeableMeasurement = (
  measurements: readonly MeasurementReportRow[]
): MeasurementReportRow | null => {
  const [firstMeasurement] = measurements;
  if (!firstMeasurement) return null;

  return measurements.reduce((current, candidate) => {
    const currentPriority = statusPriority[current.status ?? ""] ?? 0;
    const candidatePriority = statusPriority[candidate.status ?? ""] ?? 0;
    if (candidatePriority !== currentPriority) {
      return candidatePriority > currentPriority ? candidate : current;
    }
    return Math.abs(candidate.diff) > Math.abs(current.diff) ? candidate : current;
  }, firstMeasurement);
};

const differenceDescription = (measurement: MeasurementReportRow): string => {
  const difference = formatNumber(Math.abs(measurement.diff));
  if (measurement.diff === 0) {
    return `기준 ${formatNumber(measurement.ideal)}cm와 상품 ${formatNumber(measurement.product)}cm가 같아요`;
  }
  if (isLengthMeasurement(measurement.key)) {
    return `기준 ${formatNumber(measurement.ideal)}cm보다 ${difference}cm ${measurement.diff < 0 ? "짧아요" : "길어요"}`;
  }
  return `기준 ${formatNumber(measurement.ideal)}cm보다 ${difference}cm ${measurement.diff < 0 ? "좁아요" : "넓어요"}`;
};

const headlineDescription = (measurement: MeasurementReportRow): string => {
  if (measurement.diff === 0) return "평소 핏에 가까워요";
  if (isLengthMeasurement(measurement.key)) {
    return measurement.diff < 0 ? "짧게 느껴질 수 있어요" : "길게 느껴질 수 있어요";
  }
  return measurement.diff < 0 ? "타이트할 수 있어요" : "여유가 있을 수 있어요";
};

const wearingDescription = (measurement: MeasurementReportRow): string => {
  if (measurement.diff === 0) {
    return "평소 즐겨 입는 옷과 비슷한 위치와 여유를 기대할 수 있어요.";
  }
  if (isLengthMeasurement(measurement.key)) {
    if (measurement.key === "rise") {
      return measurement.diff < 0
        ? "앉거나 움직일 때 밑위가 더 타이트하게 느껴질 수 있어요."
        : "허리선과 밑위에 조금 더 여유가 생기는 방향이에요.";
    }
    return measurement.diff < 0
      ? "평소보다 짧게 끝나는 느낌이 날 수 있어요."
      : "평소보다 길게 떨어지는 실루엣을 기대할 수 있어요.";
  }
  return measurement.diff < 0
    ? "몸에 붙는 핏을 의도한 게 아니라면, 이 부위가 먼저 답답하게 느껴질 수 있어요."
    : "평소보다 몸에서 살짝 떨어져, 여유 있는 실루엣으로 보일 수 있어요.";
};

const summaryUsageDescription = (measurement: MeasurementReportRow): string => {
  if (measurement.diff === 0) {
    return "평소처럼 입고 싶다면 무난한 선택이에요.";
  }
  if (isLengthMeasurement(measurement.key)) {
    return measurement.diff < 0
      ? "평소보다 짧은 비율을 원할 때 더 자연스러워요."
      : "평소보다 길게 떨어지는 비율을 좋아한다면 자연스러워요.";
  }
  if (measurement.key === "waist_width" || measurement.key === "hip_width") {
    return measurement.diff < 0
      ? "앉거나 움직이는 시간이 많다면 이 부위의 여유를 한 번 더 확인해 보세요."
      : "편안한 착용감과 여유 있는 하체 실루엣을 원할 때 자연스러워요.";
  }
  return measurement.diff < 0
    ? "얇은 이너에는 괜찮지만, 레이어드를 자주 한다면 답답할 수 있어요."
    : "편안한 착용감이나 여유 있는 실루엣을 원한다면 자연스러워요.";
};

const findAlternative = (reportInput: FitReportInput): SizeFitOption | undefined =>
  reportInput.sizeOptions.find((option) =>
    option.sizeLabel !== reportInput.recommendation.recommendedSize
  );

const alternativeSentence = (
  reportInput: FitReportInput,
  primaryMeasurement: MeasurementReportRow
): string => {
  const alternative = findAlternative(reportInput);
  const alternativeScore = reportInput.sizeScores.find((score) =>
    score.sizeLabel !== reportInput.recommendation.recommendedSize
  );
  if (!alternative && !alternativeScore) {
    return "비교 가능한 다른 사이즈가 없어, 이 부위의 실측을 우선 확인하는 편이 좋아요.";
  }

  const alternativeLabel = alternative?.sizeLabel ?? alternativeScore?.sizeLabel;
  if (!alternativeLabel) {
    return "다른 사이즈의 실측도 함께 확인해 보세요.";
  }

  const alternativeMeasurement = alternative?.measurements.find((measurement) =>
    measurement.key === primaryMeasurement.key
  );
  if (!alternative || !alternativeMeasurement) {
    const alternativeFitScore = alternativeScore?.fitScore ?? alternative?.fitScore;
    return alternativeFitScore === undefined
      ? `${alternativeLabel}의 상세 치수를 확인하는 편이 좋아요.`
      : `${alternativeLabel}은 ${alternativeFitScore}점이지만, 이 리포트에 비교할 실측이 없어 상세 치수를 확인하는 편이 좋아요.`;
  }

  const difference = alternativeMeasurement.diff - primaryMeasurement.diff;
  if (primaryMeasurement.diff < 0 && difference > 0) {
    return `${alternativeLabel}은 ${primaryMeasurement.label}이 ${formatNumber(difference)}cm 더 여유 있어, 편안함을 우선한다면 함께 비교해 볼 만해요.`;
  }
  if (primaryMeasurement.diff > 0 && difference < 0) {
    return `${alternativeLabel}은 ${primaryMeasurement.label} 여유가 ${formatNumber(Math.abs(difference))}cm 줄어, 덜 루즈한 느낌을 원할 때 대안이 될 수 있어요.`;
  }
  return `${alternativeLabel}은 ${alternative.fitScore}점으로, 선호하는 실루엣에 따라 함께 비교해 볼 수 있어요.`;
};

const tradeoffDescription = (measurement: MeasurementReportRow): string => {
  if (measurement.diff === 0) return "특별히 감수할 차이";
  if (isLengthMeasurement(measurement.key)) {
    return measurement.diff < 0 ? "짧은 길이감" : "긴 길이감";
  }
  return measurement.diff < 0 ? "타이트함" : "여유감";
};

const recommendationChoice = (
  reportInput: FitReportInput,
  primaryMeasurement: MeasurementReportRow
): string => {
  const alternative = findAlternative(reportInput);
  if (!alternative) {
    return `슬림한 핏을 원한다면 ${reportInput.recommendation.recommendedSize}를 선택하고, 편안함을 우선한다면 다른 사이즈의 실측도 확인해 보세요.`;
  }
  if (primaryMeasurement.diff < 0) {
    return `슬림한 핏을 원한다면 ${reportInput.recommendation.recommendedSize}를, ${primaryMeasurement.label}의 편안함을 우선한다면 ${alternative.sizeLabel}을 함께 비교해 보세요.`;
  }
  if (primaryMeasurement.diff > 0) {
    return `여유 있는 핏을 원한다면 ${reportInput.recommendation.recommendedSize}를, 더 정돈된 실루엣을 원한다면 ${alternative.sizeLabel}을 함께 비교해 보세요.`;
  }
  return `평소처럼 입고 싶다면 ${reportInput.recommendation.recommendedSize}를 선택하고, 다른 사이즈는 원하는 여유에 따라 비교해 보세요.`;
};

export const buildFallbackMeasurementAnalysisText = (measurement: MeasurementReportRow): string =>
  `${measurement.label}은 상품 ${formatNumber(measurement.product)}cm로, ${differenceDescription(measurement)}. ` +
  wearingDescription(measurement);

export const buildFallbackFitReport = (reportInput: FitReportInput): FitReportJson => {
  const primaryMeasurement = mostNoticeableMeasurement(reportInput.measurements);
  const recommendedSize = reportInput.recommendation.recommendedSize;

  if (!primaryMeasurement) {
    return {
      title: `${recommendedSize} 사이즈를 먼저 확인해 보세요`,
      summary: `${recommendedSize} 사이즈의 비교 가능한 실측이 부족해요.\n\n상품 상세 치수와 평소 입는 옷의 수치를 함께 확인해 보세요.\n\n특히 자주 신경 쓰는 부위를 먼저 비교하는 편이 좋아요.`,
      recommendationReason: `${recommendedSize}가 현재 계산된 추천 사이즈예요.\n실측이 있는 다른 사이즈도 함께 확인해 보세요.\n평소 선호하는 실루엣과 가장 가까운 쪽을 선택해 보세요.`,
      measurementAnalysis: [],
      cautions: ["소재의 신축성과 두께에 따라 실제 착용감은 달라질 수 있어요."],
      nextActions: ["상품 상세의 실측과 평소 입는 옷의 수치를 비교해 보세요."]
    };
  }

  const balanced = isBalanced(reportInput.measurements);
  const title = balanced
    ? `${recommendedSize}, 평소 핏에 가까워요`
    : `${recommendedSize} ${primaryMeasurement.label}이 ${headlineDescription(primaryMeasurement)}`;
  const summary = balanced
    ? `${recommendedSize}는 평소 핏에 가까워요.\n\n비교한 부위가 기준과 크게 다르지 않아, 익숙하게 입던 실루엣을 기대할 수 있어요.\n\n단독 착용을 기준으로 보면 무난한 선택이에요.`
    : `${recommendedSize}는 ${primaryMeasurement.label}이 ${headlineDescription(primaryMeasurement)}.\n\n${differenceDescription(primaryMeasurement)}.\n\n${summaryUsageDescription(primaryMeasurement)}`;

  return {
    title,
    summary,
    recommendationReason:
      `${recommendedSize}가 ${reportInput.recommendation.fitScore}점으로 가장 높은 선택이지만, ${primaryMeasurement.label}의 ${tradeoffDescription(primaryMeasurement)}은 감수해야 해요. ` +
        `${alternativeSentence(reportInput, primaryMeasurement)} ` +
        recommendationChoice(reportInput, primaryMeasurement),
    measurementAnalysis: reportInput.measurements.map((measurement) => ({
      measurement: measurement.label,
      text: buildFallbackMeasurementAnalysisText(measurement)
    })),
    cautions: ["소재의 신축성과 두께에 따라 같은 실측 차이도 다르게 느껴질 수 있어요."],
    nextActions: [
      `${primaryMeasurement.label}이 평소 선호하는 실루엣과 맞는지 확인해 보세요.`,
      "레이어드할 예정이라면 가장 타이트한 부위의 여유를 우선 확인해 보세요."
    ]
  };
};
