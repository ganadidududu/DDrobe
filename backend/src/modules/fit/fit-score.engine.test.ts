import assert from "node:assert/strict";
import { runFitAccuracyFixtureTests } from "./fit-score.accuracy-fixtures";
import {
  applyFeedbackOffsetsToProfile,
  applyFeedbackWeightMultipliers,
  calculateDynamicWeightsByReferenceVariance,
  calculateFitScoreForReferenceProfile,
  calculateReferenceFitProfile,
  calculateStandardDeviation,
  getWeightsByCategory,
  recommendBestSizeWithReferences
} from "./fit-score.engine";
import type {
  ExternalProductSizeInput,
  FeedbackFitProfile,
  FitScoreReasonCode,
  MeasurementWeights,
  RecommendationConfidence,
  ReferenceClothingInput
} from "./fit.types";

const sumWeights = (weights: MeasurementWeights): number =>
  Number(Object.values(weights).reduce((sum, weight) => sum + (weight ?? 0), 0).toFixed(4));

const references: ReferenceClothingInput[] = [
  {
    id: "ref-a",
    fitType: "regular",
    preferenceScore: 100,
    measurements: {
      shoulder_width: 56,
      chest_width: 60,
      total_length: 70,
      sleeve_length: 61
    }
  },
  {
    id: "ref-b",
    fitType: "regular",
    preferenceScore: 100,
    measurements: {
      shoulder_width: 56.5,
      chest_width: 62,
      total_length: 70.5,
      sleeve_length: 66
    }
  },
  {
    id: "ref-c",
    fitType: "regular",
    preferenceScore: 100,
    measurements: {
      shoulder_width: 56,
      chest_width: 59,
      total_length: 71
    }
  }
];

const baseTopWeights = getWeightsByCategory("hoodie");

assert.equal(calculateStandardDeviation([56, 56.5, 56]), 0.236);

const singleReferenceWeights = calculateDynamicWeightsByReferenceVariance(baseTopWeights, [references[0]]);
assert.deepEqual(singleReferenceWeights.dynamicWeights, baseTopWeights);
assert.equal(singleReferenceWeights.weightingStrategy, "base_static");

const dynamicResult = calculateDynamicWeightsByReferenceVariance(baseTopWeights, references);
assert.equal(dynamicResult.weightingStrategy, "reference_variance_v1");
assert.equal(sumWeights(dynamicResult.dynamicWeights), 1);
assert.ok((dynamicResult.dynamicWeights.shoulder_width ?? 0) > (baseTopWeights.shoulder_width ?? 0));
assert.ok((dynamicResult.dynamicWeights.sleeve_length ?? 0) < (baseTopWeights.sleeve_length ?? 0));
assert.equal(dynamicResult.referenceVariance.sleeve_length?.sampleCount, 2);

const missingValueReferences: ReferenceClothingInput[] = [
  { id: "ref-a", fitType: "regular", measurements: { shoulder_width: 56, chest_width: 60 } },
  { id: "ref-b", fitType: "regular", measurements: { shoulder_width: 56.5 } },
  { id: "ref-c", fitType: "regular", measurements: { shoulder_width: 56 } }
];
const missingResult = calculateDynamicWeightsByReferenceVariance(baseTopWeights, missingValueReferences);
assert.equal(missingResult.referenceVariance.shoulder_width?.sampleCount, 3);
assert.equal(missingResult.referenceVariance.chest_width, undefined);

const bottomWeights = getWeightsByCategory("pants");
assert.equal(bottomWeights.outseam, 0.25);
assert.equal(Object.prototype.hasOwnProperty.call(bottomWeights, "inseam"), false);

const bottomReferences: ReferenceClothingInput[] = [
  {
    id: "pants-ref-a",
    fitType: "regular",
    measurements: { waist_width: 40, hip_width: 52, rise: 30, outseam: 100 }
  },
  {
    id: "pants-ref-b",
    fitType: "regular",
    measurements: { waist_width: 40.5, hip_width: 53, rise: 30, outseam: 101 }
  }
];

const externalSizes: ExternalProductSizeInput[] = [
  {
    id: "size-m",
    sizeLabel: "M",
    fitType: "regular",
    measurements: { waist_width: 40, hip_width: 52, rise: 30, outseam: 100 }
  },
  {
    id: "size-l",
    sizeLabel: "L",
    fitType: "regular",
    measurements: { waist_width: 44, hip_width: 56, rise: 32, outseam: 106 }
  }
];

const recommendation = recommendBestSizeWithReferences(bottomReferences, externalSizes, "pants");
assert.equal(recommendation.recommended.sizeLabel, "M");
assert.ok(typeof recommendation.recommended.diffs.outseam === "number");
assert.equal(recommendation.weightingStrategy, "reference_profile_v1");
assert.ok(recommendation.referenceProfile);

const profile = calculateReferenceFitProfile(bottomReferences, recommendation.dynamicWeights);
assert.deepEqual(profile.measurements, {
  waist_width: 40.25,
  hip_width: 52.5,
  rise: 30,
  outseam: 100.5
});
assert.equal(profile.tolerances.waist_width, 0.5);
assert.equal(profile.tolerances.outseam, 1);

const outlierResistantProfile = calculateReferenceFitProfile(
  [
    { id: "stable-a", fitType: "regular", measurements: { waist_width: 40 } },
    { id: "stable-b", fitType: "regular", measurements: { waist_width: 40.2 } },
    { id: "outlier", fitType: "regular", measurements: { waist_width: 50 } }
  ],
  { waist_width: 1 }
);
assert.ok((outlierResistantProfile.measurements.waist_width ?? 0) < 41);
assert.equal(outlierResistantProfile.sampleCounts.waist_width, 3);

const virtualPerfectSize: ExternalProductSizeInput = {
  id: "size-virtual-perfect",
  sizeLabel: "Virtual perfect",
  fitType: "regular",
  measurements: profile.measurements
};
const virtualPerfectScore = calculateFitScoreForReferenceProfile(
  profile,
  virtualPerfectSize,
  "pants",
  recommendation.dynamicWeights
);
assert.equal(virtualPerfectScore.finalFitScore, 100);
assert.equal(virtualPerfectScore.weightedFitDistance, 0);

const feedbackProfile: FeedbackFitProfile = {
  category: "pants",
  sampleCount: 2,
  overallSampleCount: 1,
  partSampleCount: 1,
  measurementOffsets: { waist_width: 1, hip_width: 1 },
  weightMultipliers: { waist_width: 1.2 },
  partFeedbackCounts: { waist_width: { too_small: 1 } },
  strategy: "feedback_offset_weight_v1"
};
const feedbackAdjustedProfile = applyFeedbackOffsetsToProfile(profile, feedbackProfile);
assert.equal(feedbackAdjustedProfile.measurements.waist_width, 41.25);
assert.equal(feedbackAdjustedProfile.measurements.hip_width, 53.5);

const feedbackAdjustedWeights = applyFeedbackWeightMultipliers(recommendation.dynamicWeights, feedbackProfile);
assert.equal(sumWeights(feedbackAdjustedWeights), 1);
assert.ok((feedbackAdjustedWeights.waist_width ?? 0) > (recommendation.dynamicWeights.waist_width ?? 0));

const feedbackRecommendation = recommendBestSizeWithReferences(
  bottomReferences,
  [
    {
      id: "size-original",
      sizeLabel: "Original",
      fitType: "regular",
      measurements: profile.measurements
    },
    {
      id: "size-feedback-fit",
      sizeLabel: "Feedback fit",
      fitType: "regular",
      measurements: feedbackAdjustedProfile.measurements
    }
  ],
  "pants",
  feedbackProfile
);
const feedbackFreeRecommendation = recommendBestSizeWithReferences(
  bottomReferences,
  [
    {
      id: "size-original",
      sizeLabel: "Original",
      fitType: "regular",
      measurements: profile.measurements
    },
    {
      id: "size-feedback-fit",
      sizeLabel: "Feedback fit",
      fitType: "regular",
      measurements: feedbackAdjustedProfile.measurements
    }
  ],
  "pants"
);
assert.equal(
  feedbackRecommendation.recommended.sizeLabel,
  feedbackFreeRecommendation.recommended.sizeLabel,
  "Given identical size charts, feedback availability must not change the recommended size"
);
assert.deepEqual(
  feedbackRecommendation.allSizeScores.map(({ sizeLabel, finalFitScore }) => ({ sizeLabel, finalFitScore })),
  feedbackFreeRecommendation.allSizeScores.map(({ sizeLabel, finalFitScore }) => ({ sizeLabel, finalFitScore })),
  "Given identical size charts, feedback availability must not change Fit Scores"
);
assert.equal(feedbackRecommendation.recommended.sizeLabel, "Original");
assert.equal(feedbackRecommendation.weightingStrategy, "reference_profile_v1");
assert.equal(feedbackRecommendation.feedbackProfile?.sampleCount, 2);

const oneReferenceRecommendation = recommendBestSizeWithReferences(
  [bottomReferences[0]],
  externalSizes,
  "pants"
);
const duplicatedReferenceRecommendation = recommendBestSizeWithReferences(
  [bottomReferences[0], { ...bottomReferences[0], id: "pants-ref-a-duplicate" }],
  externalSizes,
  "pants"
);
assert.deepEqual(
  oneReferenceRecommendation.allSizeScores.map(({ sizeLabel, finalFitScore }) => ({ sizeLabel, finalFitScore })),
  duplicatedReferenceRecommendation.allSizeScores.map(({ sizeLabel, finalFitScore }) => ({ sizeLabel, finalFitScore })),
  "Duplicating the same reference must not change Fit Scores"
);

const qualityReference: ReferenceClothingInput[] = [
  {
    id: "quality-reference-a",
    fitType: "regular",
    preferenceScore: 100,
    measurements: { waist_width: 40, hip_width: 52, rise: 30, outseam: 100 }
  },
  {
    id: "quality-reference-b",
    fitType: "regular",
    preferenceScore: 100,
    measurements: { waist_width: 40.4, hip_width: 52.6, rise: 30.2, outseam: 100.8 }
  }
];

const createQualitySize = (
  id: string,
  measurementSource: string,
  parsingStatus: string,
  extractionConfidence: number | null
): ExternalProductSizeInput => ({
  id,
  sizeLabel: "M",
  fitType: "regular" as const,
  measurements: { waist_width: 40.2, hip_width: 52.3, rise: 30.1, outseam: 100.4 },
  measurementQuality: {
    measurementSource,
    parsingStatus,
    extractionConfidence
  }
});

const qualityScenarios: readonly {
  readonly id: string;
  readonly measurementSource: string;
  readonly parsingStatus: string;
  readonly extractionConfidence: number | null;
  readonly expectedConfidence: RecommendationConfidence;
  readonly expectedTrusted: boolean;
  readonly expectedReasonCodes: readonly FitScoreReasonCode[];
}[] = [
  {
    id: "quality-manual",
    measurementSource: "manual",
    parsingStatus: "manual",
    extractionConfidence: null,
    expectedConfidence: "high",
    expectedTrusted: true,
    expectedReasonCodes: []
  },
  {
    id: "quality-ocr-confirmed",
    measurementSource: "ocr",
    parsingStatus: "confirmed",
    extractionConfidence: 0.96,
    expectedConfidence: "high",
    expectedTrusted: true,
    expectedReasonCodes: []
  },
  {
    id: "quality-ocr-pending",
    measurementSource: "ocr",
    parsingStatus: "pending",
    extractionConfidence: 0.96,
    expectedConfidence: "medium",
    expectedTrusted: false,
    expectedReasonCodes: ["unverified_product_measurement_status"]
  },
  {
    id: "quality-ocr-failed",
    measurementSource: "ocr",
    parsingStatus: "failed",
    extractionConfidence: 0.96,
    expectedConfidence: "medium",
    expectedTrusted: false,
    expectedReasonCodes: ["unverified_product_measurement_status"]
  },
  {
    id: "quality-ocr-mocked-status",
    measurementSource: "ocr",
    parsingStatus: "mocked",
    extractionConfidence: 0.96,
    expectedConfidence: "medium",
    expectedTrusted: false,
    expectedReasonCodes: ["unverified_product_measurement_status"]
  },
  {
    id: "quality-ocr-low-confidence",
    measurementSource: "ocr",
    parsingStatus: "parsed",
    extractionConfidence: 0.42,
    expectedConfidence: "medium",
    expectedTrusted: false,
    expectedReasonCodes: ["low_measurement_extraction_confidence"]
  }
];

const manualQualityRecommendation = recommendBestSizeWithReferences(
  qualityReference,
  [createQualitySize("quality-manual", "manual", "manual", null)],
  "pants"
);

for (const scenario of qualityScenarios) {
  const recommendation = recommendBestSizeWithReferences(
    qualityReference,
    [
      createQualitySize(
        scenario.id,
        scenario.measurementSource,
        scenario.parsingStatus,
        scenario.extractionConfidence
      )
    ],
    "pants"
  );
  const productMeasurementQuality =
    recommendation.recommended.confidenceBreakdown.dataQuality.productMeasurementQuality;

  assert.equal(
    recommendation.recommended.finalFitScore,
    manualQualityRecommendation.recommended.finalFitScore,
    `${scenario.id} must preserve the numeric fit score for identical measurements`
  );
  assert.equal(
    recommendation.recommended.recommendationConfidence,
    scenario.expectedConfidence,
    `${scenario.id} must expose the expected metadata confidence`
  );
  assert.ok(productMeasurementQuality, `${scenario.id} must expose product measurement quality`);
  assert.equal(
    productMeasurementQuality.trusted,
    scenario.expectedTrusted,
    `${scenario.id} must expose the expected product measurement trust flag`
  );
  assert.deepEqual(
    productMeasurementQuality.reasonCodes,
    scenario.expectedReasonCodes,
    `${scenario.id} must expose only its own product quality reason codes`
  );
  for (const reasonCode of scenario.expectedReasonCodes) {
    assert.ok(
      recommendation.recommended.confidenceBreakdown.reasonCodes.includes(reasonCode),
      `${scenario.id} confidence breakdown must include ${reasonCode}`
    );
  }
}

console.log("fixture passed: OCR/source quality metadata scenarios preserve score and isolate reasons");

runFitAccuracyFixtureTests();

console.log("fit-score.engine tests passed");
