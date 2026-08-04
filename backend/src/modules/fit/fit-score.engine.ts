import {
  ALGORITHM_VERSION,
  BOTTOM_CATEGORIES,
  BOTTOM_WEIGHTS,
  MEASUREMENT_BASE_TOLERANCES,
  MEASUREMENT_LABELS,
  TOP_WEIGHTS
} from "./fit.constants";
import { completeFitScore, getReferenceSampleCounts } from "./fit-score.explanation";
import type { SizeFitScoreBase } from "./fit-score.explanation";
import type {
  BestSizeRecommendation,
  Category,
  ExternalProductSizeInput,
  FeedbackFitProfile,
  FitLabel,
  FitType,
  MeasurementDiffs,
  MeasurementKey,
  MeasurementMap,
  MeasurementToleranceMap,
  MeasurementWeights,
  RecommendationConfidence,
  ReferenceFitProfile,
  ReferenceVarianceImportance,
  ReferenceVarianceMap,
  ReferenceClothingInput,
  SizeFitScore
} from "./fit.types";

const round = (value: number, digits = 2): number => Number(value.toFixed(digits));

const MINIMUM_FIT_SCORE = 0.1;
const FIT_SCORE_DECAY_DISTANCE = 8;
const HUBER_OUTLIER_THRESHOLD = 1.5;

const PROFILE_MAX_TOLERANCES: Record<MeasurementKey, number> = {
  shoulder_width: 3,
  chest_width: 5,
  total_length: 6,
  sleeve_length: 5,
  waist_width: 3,
  hip_width: 5,
  rise: 4,
  outseam: 8
};

const isNumber = (value: number | null | undefined): value is number =>
  typeof value === "number" && Number.isFinite(value);

const clamp = (value: number, minimum: number, maximum: number): number =>
  Math.max(minimum, Math.min(maximum, value));

const getPartStatus = (diff: number) => {
  if (Math.abs(diff) <= 1) return "very_similar" as const;
  if (diff < 0 && Math.abs(diff) <= 3) return "slightly_small" as const;
  if (diff > 0 && Math.abs(diff) <= 3) return "slightly_large" as const;
  return "large_gap" as const;
};

export const getWeightsByCategory = (category: Category): MeasurementWeights => {
  if (BOTTOM_CATEGORIES.includes(category)) {
    return BOTTOM_WEIGHTS;
  }
  return TOP_WEIGHTS;
};

const getMeasurementKeysFromWeights = (weights: MeasurementWeights): MeasurementKey[] =>
  Object.keys(weights) as MeasurementKey[];

const isFeedbackProfileApplied = (feedbackProfile?: FeedbackFitProfile): feedbackProfile is FeedbackFitProfile =>
  feedbackProfile?.reliability?.applied ?? Boolean(feedbackProfile && feedbackProfile.sampleCount > 0);

const getScoreGapToNextCandidate = (
  scores: SizeFitScore[],
  index: number
): number | null => {
  const nextScore = scores[index + 1];
  if (!nextScore) return null;
  return round(scores[index].finalFitScore - nextScore.finalFitScore, 2);
};

const getScoreGapForConfidence = (
  score: SizeFitScore,
  scoreGapToNextCandidate: number | null
): number => scoreGapToNextCandidate ?? score.finalFitScore;

const completeRankedScores = (
  scores: SizeFitScore[],
  measurementKeys: MeasurementKey[],
  referenceSampleCounts: Partial<Record<MeasurementKey, number>>,
  feedbackProfile: FeedbackFitProfile | undefined,
  weights: MeasurementWeights,
  tolerances?: MeasurementToleranceMap
): SizeFitScore[] =>
  scores.map((score, index) => {
    const scoreGapToNextCandidate = getScoreGapToNextCandidate(scores, index);
    const confidence = calculateRecommendationConfidence(
      score.finalFitScore,
      score.comparedMeasurements.length,
      score.weightedFitDistance,
      getScoreGapForConfidence(score, scoreGapToNextCandidate)
    );
    return completeFitScore(
      score,
      confidence,
      measurementKeys,
      scoreGapToNextCandidate,
      referenceSampleCounts,
      feedbackProfile,
      weights,
      tolerances
    );
  });

export const normalizeWeights = (weights: MeasurementWeights): MeasurementWeights => {
  const entries = (Object.entries(weights) as [MeasurementKey, number][])
    .filter(([, weight]) => isNumber(weight) && weight > 0);
  const sum = entries.reduce((total, [, weight]) => total + weight, 0);
  if (sum === 0) return {};
  let runningTotal = 0;
  return entries.reduce<MeasurementWeights>((normalized, [key, weight], index) => {
    const normalizedWeight =
      index === entries.length - 1 ? round(1 - runningTotal, 4) : round(weight / sum, 4);
    normalized[key] = normalizedWeight;
    runningTotal += normalizedWeight;
    return normalized;
  }, {});
};

export const calculateStandardDeviation = (values: number[]): number => {
  const numericValues = values.filter(isNumber);
  if (numericValues.length < 2) return 0;
  const mean = numericValues.reduce((sum, value) => sum + value, 0) / numericValues.length;
  const variance =
    numericValues.reduce((sum, value) => sum + (value - mean) ** 2, 0) / numericValues.length;
  return round(Math.sqrt(variance), 3);
};

export const collectReferenceMeasurementValues = (
  references: ReferenceClothingInput[],
  measurementKeys: MeasurementKey[]
): Partial<Record<MeasurementKey, number[]>> =>
  measurementKeys.reduce<Partial<Record<MeasurementKey, number[]>>>((collected, key) => {
    const values = references
      .map((reference) => reference.measurements[key])
      .filter(isNumber);
    collected[key] = values;
    return collected;
  }, {});

type WeightedMeasurementValue = { value: number; weight: number };

const getReferencePreferenceWeight = (reference: ReferenceClothingInput): number =>
  Math.max(1, reference.preferenceScore ?? 100);

export const calculateWeightedMedian = (values: WeightedMeasurementValue[]): number => {
  const usable = values
    .filter(({ value, weight }) => isNumber(value) && isNumber(weight) && weight > 0)
    .sort((a, b) => a.value - b.value);
  const totalWeight = usable.reduce((sum, item) => sum + item.weight, 0);
  if (totalWeight === 0) throw new Error("No weighted measurement values were provided");

  const midpoint = totalWeight / 2;
  let cumulativeWeight = 0;
  for (const item of usable) {
    cumulativeWeight += item.weight;
    if (cumulativeWeight >= midpoint) return item.value;
  }

  return usable[usable.length - 1].value;
};

const calculateWeightedMad = (values: WeightedMeasurementValue[], center: number): number =>
  calculateWeightedMedian(
    values.map(({ value, weight }) => ({ value: Math.abs(value - center), weight }))
  );

/**
 * Builds a virtual 100-point fit profile from several reference garments.
 * A weighted median supplies an outlier-resistant center, then one Huber-weighted
 * mean pass keeps preference-weighted detail without letting distant values dominate.
 */
export const calculateReferenceFitProfile = (
  references: ReferenceClothingInput[],
  weights: MeasurementWeights
): ReferenceFitProfile => {
  if (references.length === 0) throw new Error("At least one reference clothing item is required");

  const measurements: MeasurementMap = {};
  const tolerances: MeasurementToleranceMap = {};
  const robustScales: MeasurementToleranceMap = {};
  const sampleCounts: Partial<Record<MeasurementKey, number>> = {};

  for (const key of getMeasurementKeysFromWeights(weights)) {
    const values = references.flatMap((reference) => {
      const value = reference.measurements[key];
      return isNumber(value) ? [{ value, weight: getReferencePreferenceWeight(reference) }] : [];
    });
    if (values.length === 0) continue;

    const center = calculateWeightedMedian(values);
    const robustScale = round(calculateWeightedMad(values, center) * 1.4826, 3);
    const toleranceFloor = MEASUREMENT_BASE_TOLERANCES[key];
    const tolerance = round(
      clamp(robustScale, toleranceFloor, PROFILE_MAX_TOLERANCES[key]),
      3
    );
    const huberLimit = HUBER_OUTLIER_THRESHOLD * Math.max(robustScale, toleranceFloor);
    const adjustedValues = values.map((item) => {
      const distance = Math.abs(item.value - center);
      const outlierWeight = distance === 0 ? 1 : Math.min(1, huberLimit / distance);
      return { ...item, weight: item.weight * outlierWeight };
    });
    const adjustedWeightTotal = adjustedValues.reduce((sum, item) => sum + item.weight, 0);

    measurements[key] = round(
      adjustedValues.reduce((sum, item) => sum + item.value * item.weight, 0) / adjustedWeightTotal,
      3
    );
    tolerances[key] = tolerance;
    robustScales[key] = robustScale;
    sampleCounts[key] = values.length;
  }

  return {
    measurements,
    tolerances,
    robustScales,
    sampleCounts,
    strategy: "weighted_huber_profile_v1"
  };
};

const getImportanceByStdDev = (stdDev: number): ReferenceVarianceImportance => {
  if (stdDev <= 0.5) return "very_high";
  if (stdDev <= 1.5) return "high";
  if (stdDev <= 3) return "medium";
  if (stdDev <= 5) return "low";
  return "very_low";
};

const getImportanceMultiplier = (importance: ReferenceVarianceImportance): number => {
  switch (importance) {
    case "very_high":
      return 1.3;
    case "high":
      return 1.15;
    case "medium":
      return 1;
    case "low":
      return 0.85;
    case "very_low":
      return 0.7;
  }
};

export const calculateReferenceVarianceMap = (
  references: ReferenceClothingInput[],
  measurementKeys: MeasurementKey[]
): ReferenceVarianceMap => {
  const valuesByKey = collectReferenceMeasurementValues(references, measurementKeys);
  return measurementKeys.reduce<ReferenceVarianceMap>((varianceMap, key) => {
    const values = valuesByKey[key] ?? [];
    if (values.length < 2) return varianceMap;
    const stdDev = calculateStandardDeviation(values);
    varianceMap[key] = {
      stdDev,
      sampleCount: values.length,
      importance: getImportanceByStdDev(stdDev)
    };
    return varianceMap;
  }, {});
};

export const calculateDynamicWeightsByReferenceVariance = (
  baseWeights: MeasurementWeights,
  references: ReferenceClothingInput[]
): {
  dynamicWeights: MeasurementWeights;
  referenceVariance: ReferenceVarianceMap;
  weightingStrategy: "base_static" | "reference_variance_v1";
} => {
  const normalizedBaseWeights = normalizeWeights(baseWeights);
  const measurementKeys = getMeasurementKeysFromWeights(normalizedBaseWeights);

  if (references.length < 2) {
    return {
      dynamicWeights: normalizedBaseWeights,
      referenceVariance: {},
      weightingStrategy: "base_static"
    };
  }

  const referenceVariance = calculateReferenceVarianceMap(references, measurementKeys);
  const adjustedWeights = measurementKeys.reduce<MeasurementWeights>((weights, key) => {
    const baseWeight = normalizedBaseWeights[key];
    if (!isNumber(baseWeight)) return weights;
    const varianceInfo = referenceVariance[key];
    const multiplier = varianceInfo ? getImportanceMultiplier(varianceInfo.importance) : 1;
    weights[key] = baseWeight * multiplier;
    return weights;
  }, {});

  return {
    dynamicWeights: normalizeWeights(adjustedWeights),
    referenceVariance,
    weightingStrategy: Object.keys(referenceVariance).length > 0 ? "reference_variance_v1" : "base_static"
  };
};

export const applyFeedbackOffsetsToProfile = (
  profile: ReferenceFitProfile,
  feedbackProfile?: FeedbackFitProfile
): ReferenceFitProfile => {
  if (!isFeedbackProfileApplied(feedbackProfile)) return profile;

  const appliedFeedbackProfile = feedbackProfile;
  const measurements: MeasurementMap = { ...profile.measurements };
  for (const [key, offset] of Object.entries(appliedFeedbackProfile.measurementOffsets) as [MeasurementKey, number][]) {
    const current = measurements[key];
    if (isNumber(current) && isNumber(offset)) {
      measurements[key] = round(current + offset, 3);
    }
  }

  return { ...profile, measurements };
};

export const applyFeedbackWeightMultipliers = (
  weights: MeasurementWeights,
  feedbackProfile?: FeedbackFitProfile
): MeasurementWeights => {
  if (!isFeedbackProfileApplied(feedbackProfile)) return weights;

  const appliedFeedbackProfile = feedbackProfile;
  const adjustedWeights = (Object.entries(weights) as [MeasurementKey, number][])
    .reduce<MeasurementWeights>((adjusted, [key, weight]) => {
      const multiplier = appliedFeedbackProfile.weightMultipliers[key] ?? 1;
      adjusted[key] = weight * multiplier;
      return adjusted;
    }, {});

  return normalizeWeights(adjustedWeights);
};

export const calculateDiff = (
  referenceMeasurements: MeasurementMap,
  targetMeasurements: MeasurementMap
): MeasurementDiffs => {
  const keys = Object.keys({ ...referenceMeasurements, ...targetMeasurements }) as MeasurementKey[];

  return keys.reduce<MeasurementDiffs>((diffs, key) => {
    const referenceValue = referenceMeasurements[key];
    const targetValue = targetMeasurements[key];
    if (isNumber(referenceValue) && isNumber(targetValue)) {
      diffs[key] = round(targetValue - referenceValue);
    }
    return diffs;
  }, {});
};

export const calculateWeightedFitDistance = (
  reference: MeasurementMap,
  target: MeasurementMap,
  weights: MeasurementWeights
): number => {
  let weightedDistance = 0;
  let usedWeight = 0;

  for (const [key, weight] of Object.entries(weights) as [MeasurementKey, number][]) {
    const referenceValue = reference[key];
    const targetValue = target[key];
    if (!isNumber(referenceValue) || !isNumber(targetValue)) {
      continue;
    }

    weightedDistance += Math.abs(targetValue - referenceValue) * weight;
    usedWeight += weight;
  }

  if (usedWeight === 0) {
    throw new Error("No comparable measurements were provided");
  }

  return round(weightedDistance / usedWeight, 3);
};

export const convertDistanceToScore = (distance: number): number => {
  const nonNegativeDistance = Math.max(0, distance);
  const score =
    MINIMUM_FIT_SCORE +
    (100 - MINIMUM_FIT_SCORE) * Math.exp(-nonNegativeDistance / FIT_SCORE_DECAY_DISTANCE);
  return round(clamp(score, MINIMUM_FIT_SCORE, 100));
};

export const applyFitTypePenalty = (
  score: number,
  fitType: FitType,
  diffs: MeasurementDiffs
): { finalScore: number; penalty: number } => {
  let penalty = 0;
  const shoulderDiff = diffs.shoulder_width;
  const chestDiff = diffs.chest_width;
  const waistDiff = diffs.waist_width;

  if (fitType === "oversized" && isNumber(shoulderDiff) && shoulderDiff < -2) penalty += 5;
  if (fitType === "oversized" && isNumber(chestDiff) && chestDiff < -2) penalty += 5;
  if (fitType === "relaxed" && isNumber(chestDiff) && chestDiff < -2) penalty += 5;
  if (fitType === "slim" && isNumber(chestDiff) && chestDiff > 3) penalty += 3;
  if (fitType === "slim" && isNumber(waistDiff) && waistDiff > 2) penalty += 3;

  const majorDiffs = [shoulderDiff, chestDiff, waistDiff, diffs.hip_width].filter(isNumber);
  if (fitType === "regular" && majorDiffs.some((diff) => Math.abs(diff) > 4)) {
    penalty += 3;
  }

  return {
    finalScore: round(clamp(score - penalty, MINIMUM_FIT_SCORE, 100)),
    penalty
  };
};

const getAverageMajorDiff = (diffs: MeasurementDiffs, category: Category): number => {
  const keys: MeasurementKey[] = BOTTOM_CATEGORIES.includes(category)
    ? ["waist_width", "hip_width", "rise", "outseam"]
    : ["shoulder_width", "chest_width", "total_length", "sleeve_length"];
  const values = keys.map((key) => diffs[key]).filter(isNumber);
  if (values.length === 0) return 0;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
};

export const getFitLabel = (
  score: number,
  diffs: MeasurementDiffs,
  category: Category
): FitLabel => {
  if (score >= 95) return "very_good_fit";
  if (score >= 85) return "good_fit";
  if (score >= 70) return "acceptable";

  const averageDiff = getAverageMajorDiff(diffs, category);
  if (score >= 50) {
    return averageDiff < 0 ? "slightly_small" : "slightly_large";
  }

  return averageDiff < 0 ? "too_small" : "too_large";
};

type FitCommentInput = Pick<SizeFitScore, "comparedMeasurements" | "diffs" | "fitLabel" | "sizeLabel">;

export const generateFitComment = (result: FitCommentInput): string => {
  const closeMeasurements = result.comparedMeasurements
    .filter((key) => Math.abs(result.diffs[key] ?? 999) <= 1)
    .map((key) => MEASUREMENT_LABELS[key]);

  if (result.fitLabel === "very_good_fit" || result.fitLabel === "good_fit") {
    const parts = closeMeasurements.length > 0 ? closeMeasurements.join(", ") : "주요 실측";
    return `${result.sizeLabel} 사이즈를 추천합니다. 기준 의류와 ${parts} 차이가 작아 유사한 핏이 예상됩니다. 현재 선호 핏과 가장 가까운 실측 조합입니다.`;
  }

  if (result.fitLabel.includes("small")) {
    return `${result.sizeLabel} 사이즈는 기준 의류보다 작게 느껴질 수 있습니다. 한 사이즈 큰 선택지도 함께 확인하세요.`;
  }

  if (result.fitLabel.includes("large")) {
    return `${result.sizeLabel} 사이즈는 기준 의류보다 여유롭게 느껴질 수 있습니다. 원하는 핏 타입과 비교해 결정하세요.`;
  }

  return `${result.sizeLabel} 사이즈는 착용 가능한 범위입니다. 다만 일부 부위 실측 차이를 확인하는 것이 좋습니다.`;
};

export const generatePartExplanations = (diffs: MeasurementDiffs): string[] =>
  (Object.entries(diffs) as [MeasurementKey, number][])
    .filter(([, diff]) => isNumber(diff))
    .map(([key, diff]) => {
      const label = MEASUREMENT_LABELS[key];
      if (Math.abs(diff) <= 1) return `${label}은 기준 의류와 ${Math.abs(diff)}cm 차이로 매우 유사합니다.`;
      if (diff < 0) return `${label}은 기준 의류보다 ${Math.abs(diff)}cm 작아 더 타이트하게 느껴질 수 있습니다.`;
      return `${label}은 기준 의류보다 ${diff}cm 커서 더 여유롭게 느껴질 수 있습니다.`;
    });

export const calculateRecommendationConfidence = (
  score: number,
  comparedCount: number,
  weightedFitDistance: number,
  scoreGap: number
): RecommendationConfidence => {
  if (comparedCount >= 4 && score >= 85 && weightedFitDistance <= 1.5 && scoreGap >= 5) return "high";
  if (comparedCount >= 3 && score >= 70 && weightedFitDistance <= 3) return "medium";
  return "low";
};

export const calculateFitScoreForSize = (
  referenceClothing: ReferenceClothingInput,
  externalProductSize: ExternalProductSizeInput,
  category: Category,
  weights: MeasurementWeights = getWeightsByCategory(category)
): SizeFitScore => {
  const measurementKeys = getMeasurementKeysFromWeights(weights);
  const diffs = calculateDiff(referenceClothing.measurements, externalProductSize.measurements);
  const weightedFitDistance = calculateWeightedFitDistance(
    referenceClothing.measurements,
    externalProductSize.measurements,
    weights
  );
  const baseScore = convertDistanceToScore(weightedFitDistance);
  const fitType = externalProductSize.fitType ?? referenceClothing.fitType;
  const { finalScore, penalty } = applyFitTypePenalty(baseScore, fitType, diffs);
  const fitLabel = getFitLabel(finalScore, diffs, category);
  const comparedMeasurements = measurementKeys.filter((key) =>
    isNumber(diffs[key])
  );

  const result: SizeFitScoreBase = {
    externalProductSizeId: externalProductSize.id,
    sizeLabel: externalProductSize.sizeLabel,
    fitScore: baseScore,
    finalFitScore: finalScore,
    fitLabel,
    fitComment: "",
    partExplanations: [],
    partStatuses: Object.fromEntries(
      (Object.entries(diffs) as [MeasurementKey, number][]).map(([key, diff]) => [key, getPartStatus(diff)])
    ),
    recommendationConfidence: "low",
    weightedFitDistance,
    penalty,
    diffs,
    comparedMeasurements,
    measurementQuality: externalProductSize.measurementQuality,
    algorithmVersion: ALGORITHM_VERSION
  };
  const completedResult = completeFitScore(
    result,
    "low",
    measurementKeys,
    null,
    getReferenceSampleCounts([referenceClothing], measurementKeys),
    undefined,
    weights
  );

  return {
    ...completedResult,
    fitComment: generateFitComment(completedResult),
    partExplanations: generatePartExplanations(diffs)
  };
};

/**
 * Scores a size against a virtual reference profile. Each raw measurement gap is
 * divided by that measurement's learned tolerance before dynamic weights are applied.
 */
export const calculateFitScoreForReferenceProfile = (
  profile: ReferenceFitProfile,
  externalProductSize: ExternalProductSizeInput,
  category: Category,
  weights: MeasurementWeights
): SizeFitScore => {
  const measurementKeys = getMeasurementKeysFromWeights(weights);
  const diffs = calculateDiff(profile.measurements, externalProductSize.measurements);
  let weightedDistance = 0;
  let usedWeight = 0;

  for (const [key, weight] of Object.entries(weights) as [MeasurementKey, number][]) {
    const diff = diffs[key];
    const tolerance = profile.tolerances[key];
    if (!isNumber(diff) || !isNumber(tolerance) || tolerance <= 0) continue;
    weightedDistance += (Math.abs(diff) / tolerance) * weight;
    usedWeight += weight;
  }

  if (usedWeight === 0) throw new Error("No comparable measurements were provided");

  const normalizedFitDistance = round(weightedDistance / usedWeight, 3);
  const baseScore = convertDistanceToScore(normalizedFitDistance);
  const { finalScore, penalty } = applyFitTypePenalty(
    baseScore,
    externalProductSize.fitType ?? "regular",
    diffs
  );
  const fitLabel = getFitLabel(finalScore, diffs, category);
  const comparedMeasurements = measurementKeys.filter((key) =>
    isNumber(diffs[key]) && isNumber(profile.tolerances[key])
  );
  const result: SizeFitScoreBase = {
    externalProductSizeId: externalProductSize.id,
    sizeLabel: externalProductSize.sizeLabel,
    fitScore: baseScore,
    finalFitScore: finalScore,
    fitLabel,
    fitComment: "",
    partExplanations: [],
    partStatuses: Object.fromEntries(
      (Object.entries(diffs) as [MeasurementKey, number][]).map(([key, diff]) => [key, getPartStatus(diff)])
    ),
    recommendationConfidence: "low",
    weightedFitDistance: normalizedFitDistance,
    penalty,
    diffs,
    comparedMeasurements,
    measurementQuality: externalProductSize.measurementQuality,
    algorithmVersion: ALGORITHM_VERSION
  };
  const completedResult = completeFitScore(
    result,
    "low",
    measurementKeys,
    null,
    profile.sampleCounts,
    undefined,
    weights,
    profile.tolerances
  );

  return {
    ...completedResult,
    fitComment: generateFitComment(completedResult),
    partExplanations: generatePartExplanations(diffs)
  };
};

export const calculateWeightedScoreForSize = (
  referenceClothing: ReferenceClothingInput[],
  externalProductSize: ExternalProductSizeInput,
  category: Category,
  weights: MeasurementWeights = getWeightsByCategory(category)
): SizeFitScore => {
  if (referenceClothing.length === 0) {
    throw new Error("At least one reference clothing item is required");
  }

  const scoredReferences = referenceClothing.map((reference) => ({
    score: calculateFitScoreForSize(reference, externalProductSize, category, weights),
    weight: Math.max(1, reference.preferenceScore ?? 100)
  }));
  const totalWeight = scoredReferences.reduce((sum, item) => sum + item.weight, 0);
  const bestRepresentative = scoredReferences
    .map((item) => item.score)
    .sort((a, b) => b.finalFitScore - a.finalFitScore)[0];
  const finalFitScore = round(
    scoredReferences.reduce((sum, item) => sum + item.score.finalFitScore * item.weight, 0) / totalWeight
  );
  const weightedFitDistance = round(
    scoredReferences.reduce((sum, item) => sum + item.score.weightedFitDistance * item.weight, 0) / totalWeight,
    3
  );
  const comparedMeasurements = Array.from(
    new Set(scoredReferences.flatMap((item) => item.score.comparedMeasurements))
  );
  const fitLabel = getFitLabel(finalFitScore, bestRepresentative.diffs, category);

  const result: SizeFitScoreBase = {
    ...bestRepresentative,
    fitScore: finalFitScore,
    finalFitScore,
    weightedFitDistance,
    fitLabel,
    comparedMeasurements,
    fitComment: "",
    partExplanations: generatePartExplanations(bestRepresentative.diffs)
  };
  const measurementKeys = getMeasurementKeysFromWeights(weights);
  const completedResult = completeFitScore(
    result,
    result.recommendationConfidence,
    measurementKeys,
    null,
    getReferenceSampleCounts(referenceClothing, measurementKeys),
    undefined,
    weights
  );

  return { ...completedResult, fitComment: generateFitComment(completedResult) };
};

export const recommendBestSize = (
  referenceClothing: ReferenceClothingInput,
  externalProductSizes: ExternalProductSizeInput[],
  category: Category
): BestSizeRecommendation => {
  if (externalProductSizes.length === 0) {
    throw new Error("At least one external product size is required");
  }

  const allSizeScores = externalProductSizes
    .map((size) => calculateFitScoreForSize(referenceClothing, size, category))
    .sort((a, b) => b.finalFitScore - a.finalFitScore);
  const normalizedWeights = normalizeWeights(getWeightsByCategory(category));
  const measurementKeys = getMeasurementKeysFromWeights(normalizedWeights);
  const rankedScores = completeRankedScores(
    allSizeScores,
    measurementKeys,
    getReferenceSampleCounts([referenceClothing], measurementKeys),
    undefined,
    normalizedWeights
  );

  return {
    recommended: rankedScores[0],
    allSizeScores: rankedScores,
    baseWeights: normalizedWeights,
    dynamicWeights: normalizedWeights,
    referenceVariance: {},
    weightingStrategy: "base_static"
  };
};

export const recommendBestSizeWithReferences = (
  referenceClothing: ReferenceClothingInput[],
  externalProductSizes: ExternalProductSizeInput[],
  category: Category,
  feedbackProfile?: FeedbackFitProfile
): BestSizeRecommendation => {
  if (externalProductSizes.length === 0) {
    throw new Error("At least one external product size is required");
  }

  const baseWeights = normalizeWeights(getWeightsByCategory(category));
  const { dynamicWeights, referenceVariance } =
    calculateDynamicWeightsByReferenceVariance(baseWeights, referenceClothing);
  const referenceProfile = calculateReferenceFitProfile(referenceClothing, dynamicWeights);

  const allSizeScores = externalProductSizes
    .map((size) => calculateFitScoreForReferenceProfile(referenceProfile, size, category, dynamicWeights))
    .sort((a, b) => b.finalFitScore - a.finalFitScore);
  const measurementKeys = getMeasurementKeysFromWeights(dynamicWeights);
  const rankedScores = completeRankedScores(
    allSizeScores,
    measurementKeys,
    referenceProfile.sampleCounts,
    undefined,
    dynamicWeights,
    referenceProfile.tolerances
  );

  return {
    recommended: rankedScores[0],
    allSizeScores: rankedScores,
    baseWeights,
    dynamicWeights,
    referenceVariance,
    weightingStrategy: "reference_profile_v1",
    referenceProfile,
    feedbackProfile
  };
};
