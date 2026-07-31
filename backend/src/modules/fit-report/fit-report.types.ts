import type { Category, FitType, JsonObject, MeasurementKey, MeasurementMap } from "../../shared/types/database";
import type { FeedbackReliabilityStatus, FitScoreReasonCode } from "../fit/fit.types";

export type ReportStyle = "concise_but_explanatory" | "detailed" | "short";

export interface MeasurementReportRow {
  key: MeasurementKey;
  label: string;
  ideal: number;
  product: number;
  diff: number;
  unit: "cm";
  weight: number | null;
  tolerance: number | null;
  status: string | null;
}

export interface SizeScoreReportRow {
  sizeLabel: string;
  fitScore: number;
  fitLabel: string;
  weightedFitDistance: number;
  recommendationConfidence: string;
}

export interface ReferenceClothingReportSummary {
  name: string;
  category: Category;
  fitType: FitType;
  sizeLabel: string | null;
  preferenceScore: number;
  measurements: MeasurementMap;
}

export interface ConfidenceReasonReportSummary {
  code: FitScoreReasonCode;
  explanation: string;
}

export interface MissingMeasurementReportSummary {
  comparedMeasurementCount: number | null;
  comparedMeasurements: MeasurementKey[];
  missingMeasurementKeys: MeasurementKey[];
  summary: "complete" | "sparse" | "unavailable";
}

export interface DataQualityReportSummary {
  comparedMeasurementRatio: number | null;
  missingMeasurementKeys: MeasurementKey[];
  summary: "complete" | "sparse" | "unavailable";
}

export interface FeedbackReliabilityReportSummary {
  applied: boolean;
  sampleCount: number;
  overallSampleCount: number;
  partSampleCount: number;
  status: FeedbackReliabilityStatus | "unavailable";
  weightedSampleCount: number;
  summary: FeedbackReliabilityStatus | "unavailable";
}

export interface ExplanationFactorReportSummary {
  measurement: MeasurementKey;
  label: string;
  diff: number;
  weightedImpact: number;
  status: string;
}

export interface FitReportExplanationSummary {
  confidenceReasons: ConfidenceReasonReportSummary[];
  missingMeasurementSummary: MissingMeasurementReportSummary;
  dataQualitySummary: DataQualityReportSummary;
  feedbackReliability: FeedbackReliabilityReportSummary;
  topExplanationFactors: ExplanationFactorReportSummary[];
}

export interface FitReportInput {
  locale: "ko-KR";
  reportStyle: ReportStyle;
  engineVersion: string;
  recommendation: {
    recommendedSize: string;
    fitScore: number;
    fitLabel: string;
    recommendationConfidence: string;
    weightedFitDistance: number;
    scoreGapToSecond: number | null;
    weightingStrategy: string | null;
  };
  explanation: FitReportExplanationSummary;
  targetProduct: {
    productName: string;
    brand: string | null;
    mallName: string | null;
    category: Category;
    fitType: FitType;
    selectedSizeLabel: string;
    recommendedSizeLabel: string;
  };
  referenceClothingSummary: ReferenceClothingReportSummary[];
  idealFitNumbers: {
    measurements: MeasurementMap;
    tolerances: Partial<Record<MeasurementKey, number>>;
    weights: Partial<Record<MeasurementKey, number>>;
  };
  measurements: MeasurementReportRow[];
  sizeScores: SizeScoreReportRow[];
  feedbackPersonalization: {
    applied: boolean;
    sampleCount: number;
    measurementOffsets: JsonObject;
    weightMultipliers: JsonObject;
    partFeedbackCounts: JsonObject;
  };
  chartData: FitReportChartData;
}

export interface FitReportChartData {
  idealVsProduct: Array<{
    measurement: MeasurementKey;
    label: string;
    ideal: number;
    product: number;
    diff: number;
    status: string | null;
  }>;
  differenceBar: Array<{
    measurement: MeasurementKey;
    label: string;
    diff: number;
    direction: "larger" | "smaller" | "same";
    status: string | null;
  }>;
  sizeScoreRanking: SizeScoreReportRow[];
  feedbackAdjustment: Array<{
    measurement: MeasurementKey;
    label: string;
    offset: number;
    weightMultiplier: number;
  }>;
}

export interface FitReportJson {
  title: string;
  summary: string;
  recommendationReason: string;
  measurementAnalysis: Array<{
    measurement: string;
    text: string;
  }>;
  cautions: string[];
  nextActions: string[];
}

export interface GenerateFitReportOptions {
  selectedSizeLabel?: string;
  style?: ReportStyle;
  includeDebug?: boolean;
}

export interface GenerateFitReportResult {
  fitAnalysisResultId: string;
  source: "openrouter" | "fallback";
  modelName: string;
  promptVersion: "fit_report_v6";
  report: FitReportJson;
  chartData: FitReportChartData;
  reportInput?: FitReportInput;
  prompt?: string;
}
