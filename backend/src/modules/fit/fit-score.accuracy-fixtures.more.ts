import {
  bottomReference,
  bottomSamples,
  comparedBottom,
  regularReference,
  regularSize
} from "./fit-score.accuracy-fixtures.data";
import type { AccuracyFixture } from "./fit-score.accuracy-fixtures.data";

export const fitAccuracyAdditionalFixtures: readonly AccuracyFixture[] = [
  {
    name: "ambiguous size gap keeps deterministic recommendation with medium confidence",
    category: "pants",
    references: bottomReference,
    sizes: [
      regularSize({
        id: "ambiguous-size-m",
        sizeLabel: "M",
        measurements: { waist_width: 40.1, hip_width: 52.3, rise: 30.1, outseam: 100.3 }
      }),
      regularSize({
        id: "ambiguous-size-l",
        sizeLabel: "L",
        measurements: { waist_width: 40.3, hip_width: 52.4, rise: 30.1, outseam: 100.5 }
      })
    ],
    expectedSizeLabel: "M",
    expectedScoreBand: { min: 90, max: 100 },
    expectedComparedMeasurements: comparedBottom,
    expectedConfidence: "medium",
    expectedWeightingStrategy: "reference_profile_v1",
    expectedReasonCodes: ["small_score_gap"]
  },
  {
    name: "feedback metadata does not alter measurement-only recommendation",
    category: "pants",
    references: bottomReference,
    feedbackProfile: {
      category: "pants",
      sampleCount: 4,
      overallSampleCount: 2,
      partSampleCount: 2,
      measurementOffsets: { waist_width: 1, hip_width: 1 },
      weightMultipliers: { waist_width: 1.2, hip_width: 1.1 },
      partFeedbackCounts: { waist_width: { too_small: 2 } },
      strategy: "feedback_offset_weight_v1"
    },
    sizes: [
      regularSize({
        id: "feedback-original",
        sizeLabel: "Original M",
        measurements: { waist_width: 40.2, hip_width: 52.3, rise: 30.1, outseam: 100.4 }
      }),
      regularSize({
        id: "feedback-preferred",
        sizeLabel: "Feedback L",
        measurements: { waist_width: 41.2, hip_width: 53.3, rise: 30.1, outseam: 100.4 }
      })
    ],
    expectedSizeLabel: "Original M",
    expectedScoreBand: { min: 90, max: 100 },
    expectedComparedMeasurements: comparedBottom,
    expectedConfidence: "high",
    expectedWeightingStrategy: "reference_profile_v1",
    expectedFeedbackSampleCount: 4,
    expectedReasonCodes: []
  },
  {
    name: "low data confidence stays low when only two measurements are comparable",
    category: "hoodie",
    references: [
      regularReference({ id: "low-data-ref-a", measurements: { shoulder_width: 50, chest_width: 58 } }),
      regularReference({ id: "low-data-ref-b", measurements: { shoulder_width: 50.2, chest_width: 58.4 } })
    ],
    sizes: [
      regularSize({ id: "low-data-size-m", sizeLabel: "M", measurements: { shoulder_width: 50.1, chest_width: 58.2 } }),
      regularSize({ id: "low-data-size-l", sizeLabel: "L", measurements: { shoulder_width: 53, chest_width: 63 } })
    ],
    expectedSizeLabel: "M",
    expectedScoreBand: { min: 90, max: 100 },
    expectedComparedMeasurements: ["shoulder_width", "chest_width"],
    expectedConfidence: "low",
    expectedWeightingStrategy: "reference_profile_v1",
    expectedReferenceSamples: { shoulder_width: 2, chest_width: 2 },
    expectedReasonCodes: ["missing_measurements"]
  },
  {
    name: "data-quality degraded confidence follows sparse product measurements",
    category: "pants",
    references: bottomReference,
    sizes: [
      regularSize({ id: "quality-size-m", sizeLabel: "M", measurements: { waist_width: 40.2 } }),
      regularSize({ id: "quality-size-l", sizeLabel: "L", measurements: { waist_width: 44 } })
    ],
    expectedSizeLabel: "M",
    expectedScoreBand: { min: 90, max: 100 },
    expectedComparedMeasurements: ["waist_width"],
    expectedConfidence: "low",
    expectedWeightingStrategy: "reference_profile_v1",
    expectedReferenceSamples: bottomSamples,
    expectedReasonCodes: [
      "insufficient_comparable_measurements",
      "missing_measurements",
      "data_quality_unverified_or_sparse"
    ]
  }
];
