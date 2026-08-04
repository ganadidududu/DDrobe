import { createHttpError } from "../../shared/utils/http-error";
import { rowToMeasurements } from "../../shared/utils/measurements";
import {
  buildChartData,
  buildMeasurementRows,
  getReferenceIds,
  getScoreGapToSecond,
  getSelectedProductSize,
  normalizeSizeScores
} from "./fit-report.chart-data";
import { buildExplanationSummary } from "./fit-report.explanation";
import {
  buildReferenceSummary,
  loadExternalProduct,
  loadExternalProductSizes,
  loadFitResult
} from "./fit-report.repository";
import {
  asNumber,
  getFeedbackApplied,
  pickNumericMap,
  pickWeightMap
} from "./fit-report.result-details";
import { parseResultDetails } from "./fit-report.result-details.sanitizer";
import type { FitReportInput, GenerateFitReportOptions } from "./fit-report.types";

export const buildFitReportInput = async (
  userId: string,
  fitAnalysisResultId: string,
  options: GenerateFitReportOptions = {}
): Promise<FitReportInput> => {
  const fitResult = await loadFitResult(userId, fitAnalysisResultId);
  const details = parseResultDetails(fitResult.result_details);
  const externalProduct = await loadExternalProduct(userId, fitResult.external_product_id);
  const externalSizes = await loadExternalProductSizes(userId, fitResult.external_product_id);
  const selectedSizeLabel = options.selectedSizeLabel ?? fitResult.recommended_size_label;
  const selectedSize = getSelectedProductSize(
    externalSizes,
    selectedSizeLabel,
    fitResult.recommended_external_product_size_id
  );
  if (!selectedSize) throw createHttpError(404, "External product size was not found");

  const referenceSummary = await buildReferenceSummary(userId, getReferenceIds(fitResult, details));
  const idealMeasurements = pickNumericMap(details.referenceProfile?.measurements);
  const productMeasurements = rowToMeasurements(selectedSize);
  const sizeScores = normalizeSizeScores(details.allSizeScores, fitResult);
  const measurementRows = buildMeasurementRows(idealMeasurements, productMeasurements, details);
  const sizeOptions = sizeScores.flatMap((score) => {
    const size = externalSizes.find((candidate) => candidate.size_label === score.sizeLabel);
    if (!size) return [];
    return [{
      sizeLabel: score.sizeLabel,
      fitScore: score.fitScore,
      fitLabel: score.fitLabel,
      measurements: buildMeasurementRows(idealMeasurements, rowToMeasurements(size), details)
    }];
  });

  return {
    locale: "ko-KR",
    reportStyle: options.style ?? "concise_but_explanatory",
    engineVersion: fitResult.algorithm_version,
    recommendation: {
      recommendedSize: fitResult.recommended_size_label,
      fitScore: fitResult.fit_score,
      fitLabel: fitResult.fit_label,
      recommendationConfidence: fitResult.recommendation_confidence,
      weightedFitDistance: fitResult.weighted_fit_distance,
      scoreGapToSecond: getScoreGapToSecond(sizeScores),
      weightingStrategy: typeof details.weightingStrategy === "string" ? details.weightingStrategy : null
    },
    explanation: buildExplanationSummary(details),
    targetProduct: {
      productName: externalProduct.product_name,
      brand: externalProduct.brand,
      mallName: externalProduct.mall_name,
      category: externalProduct.category,
      fitType: externalProduct.fit_type,
      selectedSizeLabel: selectedSize.size_label,
      recommendedSizeLabel: fitResult.recommended_size_label
    },
    referenceClothingSummary: referenceSummary,
    idealFitNumbers: {
      measurements: idealMeasurements,
      tolerances: pickWeightMap(details.referenceProfile?.tolerances),
      weights: pickWeightMap(details.dynamicWeights)
    },
    measurements: measurementRows,
    sizeScores,
    sizeOptions,
    feedbackPersonalization: {
      applied: getFeedbackApplied(details),
      sampleCount: asNumber(details.feedbackProfile?.sampleCount) ?? 0,
      measurementOffsets: details.feedbackProfile?.measurementOffsets ?? {},
      weightMultipliers: details.feedbackProfile?.weightMultipliers ?? {},
      partFeedbackCounts: details.feedbackProfile?.partFeedbackCounts ?? {}
    },
    chartData: buildChartData(measurementRows, sizeScores, details)
  };
};
