import {
  applyProductMeasurementQualityToConfidence,
  getProductMeasurementQualitySummary
} from "./fit-score.measurement-quality";
import type {
  ConfidenceBreakdown,
  FeedbackFitProfile,
  FitScoreContribution,
  FitScoreExplanation,
  FitScoreReasonCode,
  MeasurementDiffs,
  MeasurementKey,
  MeasurementToleranceMap,
  MeasurementWeights,
  ProductMeasurementQualitySummary,
  RecommendationConfidence,
  ReferenceClothingInput,
  SizeFitScore
} from "./fit.types";

const round = (value: number, digits = 2): number => Number(value.toFixed(digits));

const MIN_COMPARABLE_MEASUREMENTS_FOR_CONFIDENCE = 3;
const INSUFFICIENT_COMPARABLE_MEASUREMENT_COUNT = 1;
const CLEAR_SCORE_GAP = 5;

export type SizeFitScoreBase = Omit<SizeFitScore, "scoreExplanation" | "confidenceBreakdown">;

const isNumber = (value: number | null | undefined): value is number =>
  typeof value === "number" && Number.isFinite(value);

const getPartStatus = (diff: number): FitScoreContribution["status"] => {
  if (Math.abs(diff) <= 1) return "very_similar";
  if (diff < 0 && Math.abs(diff) <= 3) return "slightly_small";
  if (diff > 0 && Math.abs(diff) <= 3) return "slightly_large";
  return "large_gap";
};

export const getReferenceSampleCounts = (
  references: ReferenceClothingInput[],
  measurementKeys: MeasurementKey[]
): Partial<Record<MeasurementKey, number>> =>
  measurementKeys.reduce<Partial<Record<MeasurementKey, number>>>((sampleCounts, key) => {
    const count = references.filter((reference) => isNumber(reference.measurements[key])).length;
    if (count > 0) sampleCounts[key] = count;
    return sampleCounts;
  }, {});

const getMissingMeasurementKeys = (
  measurementKeys: MeasurementKey[],
  comparedMeasurements: MeasurementKey[]
): MeasurementKey[] =>
  measurementKeys.filter((key) => !comparedMeasurements.includes(key));

const isFeedbackProfileApplied = (feedbackProfile: FeedbackFitProfile | undefined): boolean =>
  feedbackProfile?.reliability?.applied ?? Boolean(feedbackProfile && feedbackProfile.sampleCount > 0);

const getScoreReasonCodes = (
  comparedMeasurements: MeasurementKey[],
  missingMeasurementKeys: MeasurementKey[],
  scoreGapToNextCandidate: number | null,
  productMeasurementQuality: ProductMeasurementQualitySummary | undefined
): FitScoreReasonCode[] => {
  const reasonCodes: FitScoreReasonCode[] = [];

  if (comparedMeasurements.length <= INSUFFICIENT_COMPARABLE_MEASUREMENT_COUNT) {
    reasonCodes.push("insufficient_comparable_measurements");
  }
  if (missingMeasurementKeys.length > 0) reasonCodes.push("missing_measurements");
  if (scoreGapToNextCandidate !== null && scoreGapToNextCandidate < CLEAR_SCORE_GAP) {
    reasonCodes.push("small_score_gap");
  }

  if (
    comparedMeasurements.length < MIN_COMPARABLE_MEASUREMENTS_FOR_CONFIDENCE ||
    missingMeasurementKeys.length > 0
  ) {
    reasonCodes.push("data_quality_unverified_or_sparse");
  }

  reasonCodes.push(...(productMeasurementQuality?.reasonCodes ?? []));

  return reasonCodes;
};

const getTopContributingParts = (
  comparedMeasurements: MeasurementKey[],
  diffs: MeasurementDiffs,
  weights: MeasurementWeights,
  tolerances?: MeasurementToleranceMap
): FitScoreContribution[] =>
  comparedMeasurements
    .flatMap((key) => {
      const diff = diffs[key];
      const weight = weights[key];
      if (!isNumber(diff) || !isNumber(weight)) return [];
      const tolerance = tolerances?.[key];
      const normalizedImpact = isNumber(tolerance) && tolerance > 0
        ? (Math.abs(diff) / tolerance) * weight
        : Math.abs(diff) * weight;
      return [{
        key,
        diff,
        weightedImpact: round(normalizedImpact, 4),
        status: getPartStatus(diff)
      }];
    })
    .sort((a, b) => b.weightedImpact - a.weightedImpact)
    .slice(0, 3);

const buildScoreMetadata = (
  score: SizeFitScoreBase,
  confidence: RecommendationConfidence,
  measurementKeys: MeasurementKey[],
  scoreGapToNextCandidate: number | null,
  referenceSampleCounts: Partial<Record<MeasurementKey, number>>,
  feedbackProfile: FeedbackFitProfile | undefined,
  productMeasurementQuality: ProductMeasurementQualitySummary | undefined,
  weights: MeasurementWeights,
  tolerances?: MeasurementToleranceMap
): Pick<SizeFitScore, "scoreExplanation" | "confidenceBreakdown"> => {
  const missingMeasurementKeys = getMissingMeasurementKeys(measurementKeys, score.comparedMeasurements);
  const reasonCodes = getScoreReasonCodes(
    score.comparedMeasurements,
    missingMeasurementKeys,
    scoreGapToNextCandidate,
    productMeasurementQuality
  );
  const comparedMeasurementRatio = measurementKeys.length === 0
    ? 0
    : round(score.comparedMeasurements.length / measurementKeys.length, 4);
  const feedbackApplied = isFeedbackProfileApplied(feedbackProfile);
  const feedbackReliability = feedbackProfile?.reliability;
  const feedbackReliabilitySummary = feedbackReliability?.status ?? (feedbackApplied ? "applied" : "unavailable");

  const scoreExplanation: FitScoreExplanation = {
    comparedMeasurementCount: score.comparedMeasurements.length,
    comparedMeasurements: score.comparedMeasurements,
    missingMeasurementKeys,
    scoreGapToNextCandidate,
    normalizedDistance: score.weightedFitDistance,
    penalty: score.penalty,
    referenceSampleCounts,
    topContributingParts: getTopContributingParts(
      score.comparedMeasurements,
      score.diffs,
      weights,
      tolerances
    ),
    reasonCodes
  };
  const dataQuality: ConfidenceBreakdown["dataQuality"] = {
    comparedMeasurementRatio,
    missingMeasurementKeys,
    summary: missingMeasurementKeys.length === 0 ? "complete" : "sparse",
    ...(productMeasurementQuality ? { productMeasurementQuality } : {})
  };

  const confidenceBreakdown: ConfidenceBreakdown = {
    label: confidence,
    score: score.finalFitScore,
    comparedMeasurementCount: score.comparedMeasurements.length,
    scoreGapToNextCandidate,
    normalizedDistance: score.weightedFitDistance,
    penalty: score.penalty,
    reasonCodes,
    referenceSampleCounts,
    feedbackReliability: {
      applied: feedbackApplied,
      sampleCount: feedbackProfile?.sampleCount ?? 0,
      overallSampleCount: feedbackProfile?.overallSampleCount ?? 0,
      partSampleCount: feedbackProfile?.partSampleCount ?? 0,
      status: feedbackReliability?.status ?? (feedbackApplied ? "applied" : "unavailable"),
      weightedSampleCount: feedbackReliability?.weightedSampleCount ?? feedbackProfile?.sampleCount ?? 0,
      summary: feedbackReliabilitySummary
    },
    dataQuality
  };

  return { scoreExplanation, confidenceBreakdown };
};

export const completeFitScore = (
  score: SizeFitScoreBase,
  confidence: RecommendationConfidence,
  measurementKeys: MeasurementKey[],
  scoreGapToNextCandidate: number | null,
  referenceSampleCounts: Partial<Record<MeasurementKey, number>>,
  feedbackProfile: FeedbackFitProfile | undefined,
  weights: MeasurementWeights,
  tolerances?: MeasurementToleranceMap
): SizeFitScore => {
  const productMeasurementQuality = getProductMeasurementQualitySummary(score.measurementQuality);
  const adjustedConfidence = applyProductMeasurementQualityToConfidence(
    confidence,
    productMeasurementQuality
  );
  const metadata = buildScoreMetadata(
    score,
    adjustedConfidence,
    measurementKeys,
    scoreGapToNextCandidate,
    referenceSampleCounts,
    feedbackProfile,
    productMeasurementQuality,
    weights,
    tolerances
  );
  return { ...score, recommendationConfidence: adjustedConfidence, ...metadata };
};
