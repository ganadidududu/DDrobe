import type { ExternalProductSizeRow, FitAnalysisResultRow, MeasurementMap } from "../../shared/types/database";
import { measurementKeys } from "../../shared/utils/measurements";
import { MEASUREMENT_BASE_TOLERANCES, MEASUREMENT_LABELS } from "../fit/fit.constants";
import type { FitLabel, RecommendationConfidence } from "../fit/fit.types";
import { asNumber, round, type ResultDetails } from "./fit-report.result-details";
import type { FitReportChartData, MeasurementReportRow, SizeScoreReportRow } from "./fit-report.types";

const FIT_LABELS: readonly FitLabel[] = [
  "very_good_fit",
  "good_fit",
  "acceptable",
  "slightly_small",
  "slightly_large",
  "too_small",
  "too_large"
] as const;
const RECOMMENDATION_CONFIDENCE_LABELS: readonly RecommendationConfidence[] = ["high", "medium", "low"] as const;
const SAFE_SIZE_LABEL_CHAR_PATTERN = /^[0-9A-Za-z가-힣+\-./ ]{1,16}$/;
const NUMERIC_SIZE_LABEL_PATTERN = /^[0-9]{1,3}(?:\.[0-9])?$/;
const SIZE_LABEL_SEPARATOR_PATTERN = /\s*[/-]\s*/;
const ASCII_SIZE_LABELS: readonly string[] = [
  "XXS",
  "XS",
  "S",
  "M",
  "L",
  "XL",
  "XXL",
  "XXXL",
  "XXXXL",
  "2XS",
  "2XL",
  "3XL",
  "4XL",
  "5XL",
  "6XL",
  "7XL",
  "8XL",
  "9XL",
  "F",
  "OS",
  "OSFA",
  "FREE",
  "ONE SIZE",
  "ONESIZE"
] as const;
const KOREAN_SIZE_LABELS: readonly string[] = [
  "소",
  "중",
  "대",
  "특대",
  "프리",
  "자유",
  "스몰",
  "미디움",
  "라지",
  "엑스라지"
] as const;
const PRIVATE_LABEL_PATTERN = /(?:secret|private|token|bearer|ignore|instruction|prompt|raw|payload|ocr|user|comment|phone|email|address|leak|override)/i;
const PHONE_LABEL_PATTERN = /\d{2,4}-\d{3,4}-\d{4}/;

const isNumber = (value: unknown): value is number =>
  typeof value === "number" && Number.isFinite(value);

const isRecord = (value: unknown): value is Record<string, unknown> =>
  Boolean(value) && typeof value === "object" && !Array.isArray(value);

const isAllowedString = <T extends string>(value: string, allowedValues: readonly T[]): value is T =>
  allowedValues.some((allowedValue) => allowedValue === value);

const isFitLabel = (value: string): value is FitLabel =>
  isAllowedString(value, FIT_LABELS);

const isRecommendationConfidence = (value: string): value is RecommendationConfidence =>
  isAllowedString(value, RECOMMENDATION_CONFIDENCE_LABELS);

const isSafeSingleSizeLabel = (value: string): boolean => {
  if (value.length === 0) return false;
  const normalized = value.toUpperCase();
  if (
    ASCII_SIZE_LABELS.includes(normalized) ||
    KOREAN_SIZE_LABELS.includes(value) ||
    NUMERIC_SIZE_LABEL_PATTERN.test(value)
  ) return true;
  if (!value.endsWith("+")) return false;
  const baseLabel = value.slice(0, -1);
  return isSafeSingleSizeLabel(baseLabel);
};

const isSafeCompositeSizeLabel = (value: string): boolean => {
  if (!/[/-]/.test(value)) return false;
  const parts = value.split(SIZE_LABEL_SEPARATOR_PATTERN);
  return parts.length >= 2 && parts.length <= 3 && parts.every(isSafeSingleSizeLabel);
};

const isSafeSizeLabel = (value: string): boolean => {
  const trimmed = value.trim();
  return (
    trimmed === value &&
    SAFE_SIZE_LABEL_CHAR_PATTERN.test(value) &&
    !PRIVATE_LABEL_PATTERN.test(value) &&
    !PHONE_LABEL_PATTERN.test(value) &&
    (isSafeSingleSizeLabel(value) || isSafeCompositeSizeLabel(value))
  );
};

const getDirection = (diff: number): "larger" | "smaller" | "same" => {
  if (diff > 0) return "larger";
  if (diff < 0) return "smaller";
  return "same";
};

const getPartStatus = (
  key: keyof typeof MEASUREMENT_BASE_TOLERANCES,
  diff: number,
  learnedTolerance: number | null
): string => {
  const absDiff = Math.abs(diff);
  const similarLimit = learnedTolerance && learnedTolerance > 0
    ? learnedTolerance
    : MEASUREMENT_BASE_TOLERANCES[key];
  if (absDiff <= similarLimit) return "good";
  if (absDiff <= similarLimit * 2) return diff > 0 ? "loose" : "tight";
  return diff > 0 ? "too_loose" : "too_tight";
};

export const getSelectedProductSize = (
  sizes: readonly ExternalProductSizeRow[],
  selectedSizeLabel: string,
  recommendedExternalProductSizeId: string | null
): ExternalProductSizeRow | undefined =>
  sizes.find((size) => size.size_label === selectedSizeLabel) ??
  sizes.find((size) => size.id === recommendedExternalProductSizeId) ??
  sizes[0];

export const getScoreGapToSecond = (sizeScores: readonly SizeScoreReportRow[]): number | null => {
  if (sizeScores.length < 2) return null;
  return round(sizeScores[0].fitScore - sizeScores[1].fitScore, 2);
};

export const getReferenceIds = (
  fitResult: FitAnalysisResultRow,
  details: ResultDetails
): readonly string[] => {
  const ids = Array.isArray(details.referenceClothingIds)
    ? details.referenceClothingIds.filter((id): id is string => typeof id === "string")
    : [];
  return ids.length > 0 ? ids : [fitResult.reference_clothing_id];
};

export const buildMeasurementRows = (
  idealMeasurements: MeasurementMap,
  productMeasurements: MeasurementMap,
  details: ResultDetails
): MeasurementReportRow[] =>
  measurementKeys.flatMap((key) => {
    const ideal = idealMeasurements[key];
    const product = productMeasurements[key];
    if (!isNumber(ideal) || !isNumber(product)) return [];
    const diff = round(product - ideal, 2);
    const tolerance = asNumber(details.referenceProfile?.tolerances?.[key]);
    return [{
      key,
      label: MEASUREMENT_LABELS[key],
      ideal: round(ideal, 3),
      product: round(product, 3),
      diff,
      unit: "cm" as const,
      weight: asNumber(details.dynamicWeights?.[key]),
      tolerance,
      status: getPartStatus(key, diff, tolerance)
    }];
  });

export const buildChartData = (
  measurementRows: readonly MeasurementReportRow[],
  sizeScores: readonly SizeScoreReportRow[],
  details: ResultDetails
): FitReportChartData => ({
  idealVsProduct: measurementRows.map((row) => ({
    measurement: row.key,
    label: row.label,
    ideal: row.ideal,
    product: row.product,
    diff: row.diff,
    status: row.status
  })),
  differenceBar: measurementRows.map((row) => ({
    measurement: row.key,
    label: row.label,
    diff: row.diff,
    direction: getDirection(row.diff),
    status: row.status
  })),
  sizeScoreRanking: [...sizeScores],
  feedbackAdjustment: measurementKeys.map((key) => ({
    measurement: key,
    label: MEASUREMENT_LABELS[key],
    offset: asNumber(details.feedbackProfile?.measurementOffsets?.[key]) ?? 0,
    weightMultiplier: asNumber(details.feedbackProfile?.weightMultipliers?.[key]) ?? 1
  }))
});

export const normalizeSizeScores = (
  allSizeScores: ResultDetails["allSizeScores"],
  fitResult: FitAnalysisResultRow
): SizeScoreReportRow[] => {
  const fromDetails = Array.isArray(allSizeScores)
    ? allSizeScores.flatMap((score) => {
      if (!isRecord(score)) return [];
      const fitScore = asNumber(score.finalFitScore) ?? asNumber(score.fitScore);
      const weightedFitDistance = asNumber(score.weightedFitDistance);
      const sizeLabel = score.sizeLabel;
      const fitLabel = score.fitLabel;
      const recommendationConfidence = score.recommendationConfidence;
      if (
        typeof sizeLabel !== "string" ||
        !isSafeSizeLabel(sizeLabel) ||
        fitScore === null ||
        typeof fitLabel !== "string" ||
        !isFitLabel(fitLabel) ||
        weightedFitDistance === null ||
        typeof recommendationConfidence !== "string" ||
        !isRecommendationConfidence(recommendationConfidence)
      ) return [];
      return [{ sizeLabel, fitScore, fitLabel, weightedFitDistance, recommendationConfidence }];
    })
    : [];

  if (fromDetails.length > 0) {
    return fromDetails.sort((a, b) => b.fitScore - a.fitScore);
  }

  return [{
    sizeLabel: fitResult.recommended_size_label,
    fitScore: fitResult.fit_score,
    fitLabel: fitResult.fit_label,
    weightedFitDistance: fitResult.weighted_fit_distance,
    recommendationConfidence: fitResult.recommendation_confidence
  }];
};
