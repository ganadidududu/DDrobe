import type {
  Category,
  MeasurementKey,
  MeasurementToleranceMap,
  MeasurementWeights
} from "./fit.types";

export const ALGORITHM_VERSION = "mvp_rule_v1_7";

export const TOP_CATEGORIES: Category[] = [
  "tshirt",
  "shirt",
  "sweatshirt",
  "hoodie",
  "knit",
  "jacket",
  "coat"
];

export const BOTTOM_CATEGORIES: Category[] = ["pants", "jeans", "shorts", "skirt"];

export const TOP_WEIGHTS: MeasurementWeights = {
  shoulder_width: 0.35,
  chest_width: 0.3,
  total_length: 0.2,
  sleeve_length: 0.15
};

export const BOTTOM_WEIGHTS: MeasurementWeights = {
  waist_width: 0.35,
  hip_width: 0.25,
  rise: 0.15,
  outseam: 0.25
};

export const MEASUREMENT_BASE_TOLERANCES: Required<MeasurementToleranceMap> = {
  shoulder_width: 0.5,
  chest_width: 0.75,
  total_length: 1,
  sleeve_length: 0.75,
  waist_width: 0.5,
  hip_width: 0.75,
  rise: 0.5,
  outseam: 1
};

export const MEASUREMENT_LABELS: Record<MeasurementKey, string> = {
  total_length: "총장",
  shoulder_width: "어깨",
  chest_width: "가슴단면",
  sleeve_length: "소매",
  waist_width: "허리단면",
  hip_width: "엉덩이단면",
  rise: "밑위",
  outseam: "아웃심"
};
