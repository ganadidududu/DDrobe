import type {
  BestSizeRecommendation,
  Category,
  ExternalProductSizeInput,
  FeedbackFitProfile,
  FitScoreReasonCode,
  MeasurementKey,
  ReferenceClothingInput,
  SizeFitScore
} from "./fit.types";

export type AccuracyFixture = {
  readonly name: string;
  readonly category: Category;
  readonly references: readonly ReferenceClothingInput[];
  readonly sizes: readonly ExternalProductSizeInput[];
  readonly feedbackProfile?: FeedbackFitProfile;
  readonly expectedSizeLabel: string;
  readonly expectedScoreBand: { readonly min: number; readonly max: number };
  readonly expectedComparedMeasurements: readonly MeasurementKey[];
  readonly expectedConfidence: SizeFitScore["recommendationConfidence"];
  readonly expectedWeightingStrategy: BestSizeRecommendation["weightingStrategy"];
  readonly expectedReferenceSamples?: Partial<Record<MeasurementKey, number>>;
  readonly expectedFeedbackSampleCount?: number;
  readonly expectedReasonCodes?: readonly FitScoreReasonCode[];
};

type ReferenceFixtureInput = {
  readonly id: string;
  readonly measurements: ReferenceClothingInput["measurements"];
  readonly preferenceScore?: number;
};

type SizeFixtureInput = {
  readonly id: string;
  readonly sizeLabel: string;
  readonly measurements: ExternalProductSizeInput["measurements"];
};

const comparedTop: readonly MeasurementKey[] = [
  "shoulder_width",
  "chest_width",
  "total_length",
  "sleeve_length"
];
export const comparedBottom: readonly MeasurementKey[] = ["waist_width", "hip_width", "rise", "outseam"];

export const regularReference = (input: ReferenceFixtureInput): ReferenceClothingInput => ({
  id: input.id,
  fitType: "regular",
  preferenceScore: input.preferenceScore ?? 100,
  measurements: input.measurements
});

export const regularSize = (input: SizeFixtureInput): ExternalProductSizeInput => ({
  id: input.id,
  sizeLabel: input.sizeLabel,
  fitType: "regular",
  measurements: input.measurements
});

const topReference: readonly ReferenceClothingInput[] = [
  regularReference({
    id: "top-ref-a",
    measurements: { shoulder_width: 50, chest_width: 58, total_length: 70, sleeve_length: 62 }
  }),
  regularReference({
    id: "top-ref-b",
    preferenceScore: 96,
    measurements: { shoulder_width: 50.2, chest_width: 58.5, total_length: 70.4, sleeve_length: 62.2 }
  })
];

export const bottomReference: readonly ReferenceClothingInput[] = [
  regularReference({
    id: "bottom-ref-a",
    measurements: { waist_width: 40, hip_width: 52, rise: 30, outseam: 100 }
  }),
  regularReference({
    id: "bottom-ref-b",
    preferenceScore: 98,
    measurements: { waist_width: 40.4, hip_width: 52.6, rise: 30.2, outseam: 100.8 }
  })
];

const topSamples: Partial<Record<MeasurementKey, number>> = {
  shoulder_width: 2,
  chest_width: 2,
  total_length: 2,
  sleeve_length: 2
};

export const bottomSamples: Partial<Record<MeasurementKey, number>> = {
  waist_width: 2,
  hip_width: 2,
  rise: 2,
  outseam: 2
};

export const fitAccuracyFixtures: readonly AccuracyFixture[] = [
  {
    name: "top category close match recommends the closest regular size with high confidence",
    category: "hoodie",
    references: topReference,
    sizes: [
      regularSize({
        id: "top-size-m",
        sizeLabel: "M",
        measurements: { shoulder_width: 50.1, chest_width: 58.2, total_length: 70.2, sleeve_length: 62.1 }
      }),
      regularSize({
        id: "top-size-l",
        sizeLabel: "L",
        measurements: { shoulder_width: 53, chest_width: 63, total_length: 74, sleeve_length: 65 }
      })
    ],
    expectedSizeLabel: "M",
    expectedScoreBand: { min: 90, max: 100 },
    expectedComparedMeasurements: comparedTop,
    expectedConfidence: "high",
    expectedWeightingStrategy: "reference_profile_v1",
    expectedReferenceSamples: topSamples,
    expectedReasonCodes: []
  },
  {
    name: "bottom category close match recommends the closest pants size with high confidence",
    category: "pants",
    references: bottomReference,
    sizes: [
      regularSize({
        id: "bottom-size-m",
        sizeLabel: "M",
        measurements: { waist_width: 40.2, hip_width: 52.3, rise: 30.1, outseam: 100.4 }
      }),
      regularSize({
        id: "bottom-size-l",
        sizeLabel: "L",
        measurements: { waist_width: 43, hip_width: 56, rise: 32, outseam: 105 }
      })
    ],
    expectedSizeLabel: "M",
    expectedScoreBand: { min: 90, max: 100 },
    expectedComparedMeasurements: comparedBottom,
    expectedConfidence: "high",
    expectedWeightingStrategy: "reference_profile_v1",
    expectedReferenceSamples: bottomSamples,
    expectedReasonCodes: []
  },
  {
    name: "missing measurements still recommends from comparable top measurements",
    category: "hoodie",
    references: [
      regularReference({
        id: "missing-ref-a",
        measurements: { shoulder_width: 50, chest_width: 58, total_length: 70 }
      }),
      regularReference({
        id: "missing-ref-b",
        measurements: { shoulder_width: 50.4, chest_width: 58.5, total_length: 70.6 }
      })
    ],
    sizes: [
      regularSize({
        id: "missing-size-m",
        sizeLabel: "M",
        measurements: { shoulder_width: 50.2, chest_width: 58.2, total_length: 70.3 }
      }),
      regularSize({
        id: "missing-size-l",
        sizeLabel: "L",
        measurements: { shoulder_width: 52.5, chest_width: 62, total_length: 74 }
      })
    ],
    expectedSizeLabel: "M",
    expectedScoreBand: { min: 90, max: 100 },
    expectedComparedMeasurements: ["shoulder_width", "chest_width", "total_length"],
    expectedConfidence: "medium",
    expectedWeightingStrategy: "reference_profile_v1",
    expectedReferenceSamples: { shoulder_width: 2, chest_width: 2, total_length: 2 },
    expectedReasonCodes: ["missing_measurements"]
  },
  {
    name: "outlier reference is dampened before ranking candidate sizes",
    category: "pants",
    references: [
      regularReference({
        id: "outlier-stable-a",
        measurements: { waist_width: 40, hip_width: 52, rise: 30, outseam: 100 }
      }),
      regularReference({
        id: "outlier-stable-b",
        measurements: { waist_width: 40.2, hip_width: 52.4, rise: 30.1, outseam: 100.4 }
      }),
      regularReference({
        id: "outlier-wide",
        preferenceScore: 5,
        measurements: { waist_width: 50, hip_width: 64, rise: 35, outseam: 112 }
      })
    ],
    sizes: [
      regularSize({
        id: "outlier-size-stable",
        sizeLabel: "Stable M",
        measurements: { waist_width: 40.2, hip_width: 52.4, rise: 30.1, outseam: 100.4 }
      }),
      regularSize({
        id: "outlier-size-wide",
        sizeLabel: "Outlier XL",
        measurements: { waist_width: 50, hip_width: 64, rise: 35, outseam: 112 }
      })
    ],
    expectedSizeLabel: "Stable M",
    expectedScoreBand: { min: 85, max: 100 },
    expectedComparedMeasurements: comparedBottom,
    expectedConfidence: "high",
    expectedWeightingStrategy: "reference_profile_v1",
    expectedReferenceSamples: { waist_width: 3, hip_width: 3, rise: 3, outseam: 3 },
    expectedReasonCodes: []
  }
];
