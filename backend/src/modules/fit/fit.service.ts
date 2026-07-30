import { supabase } from "../../config/supabase";
import type { FitAnalysisResultRow } from "../../shared/types/database";
import { areCategoriesCompatible } from "../../shared/utils/category-compatibility";
import { createHttpError } from "../../shared/utils/http-error";
import { rowToMeasurements } from "../../shared/utils/measurements";
import { ALGORITHM_VERSION } from "./fit.constants";
import { buildUserFeedbackFitProfile } from "./feedback-fit-profile";
import { recommendBestSizeWithReferences } from "./fit-score.engine";
import type {
  Category,
  ExternalProductSizeInput,
  FitRecommendationResult,
  FitType,
  MeasurementMap,
  ReferenceClothingInput
} from "./fit.types";

interface RecommendFitParams {
  userId: string;
  referenceClothingId?: string;
  referenceClothingIds?: string[];
  externalProductId: string;
}

export interface PreparedFitRecommendation {
  readonly response: Omit<FitRecommendationResult, "fitAnalysisResultId">;
  readonly persistence: {
    readonly referenceClothingId: string;
    readonly externalProductId: string;
    readonly recommendedExternalProductSizeId: string;
    readonly recommendedSizeLabel: string;
    readonly fitScore: number;
    readonly fitLabel: string;
    readonly fitComment: string;
    readonly weightedFitDistance: number;
    readonly algorithmVersion: string;
    readonly recommendationConfidence: string;
    readonly resultDetails: Record<string, unknown>;
  };
}

interface DbReferenceClothing {
  id: string;
  user_id: string;
  clothing_item_id: string;
  category: string;
  fit_type: FitType;
  preference_score?: number | null;
}

interface DbClothingItem {
  id: string;
  category: string;
  fit_type: FitType;
  size_label: string | null;
}

interface DbMeasurementRow extends MeasurementMap {
  id: string;
  clothing_item_id: string;
  size_label?: string | null;
}

interface DbExternalProduct {
  id: string;
  category: string;
  fit_type: FitType;
}

interface DbExternalProductSize extends MeasurementMap {
  id: string;
  size_label: string;
  measurement_source: string | null;
  parsing_status: string | null;
  extraction_confidence: number | null;
}

const asRecord = (value: unknown): Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};

const asStringArray = (value: unknown): string[] =>
  Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];

export const prepareFitRecommendation = async ({
  userId,
  referenceClothingId,
  referenceClothingIds,
  externalProductId
}: RecommendFitParams): Promise<PreparedFitRecommendation> => {
  const selectedReferenceIds = referenceClothingIds?.length
    ? referenceClothingIds
    : referenceClothingId
      ? [referenceClothingId]
      : [];

  if (selectedReferenceIds.length === 0) {
    throw createHttpError(400, "At least one reference clothing id is required");
  }

  const { data: referenceClothing, error: referenceError } = await supabase
    .from("reference_clothing")
    .select("*")
    .eq("user_id", userId)
    .eq("is_active", true)
    .in("id", selectedReferenceIds)
    .returns<DbReferenceClothing[]>();

  if (referenceError || !referenceClothing || referenceClothing.length === 0) {
    throw createHttpError(404, "Active reference clothing was not found");
  }

  const clothingItemIds = referenceClothing.map((reference) => reference.clothing_item_id);

  const { data: clothingItems, error: itemError } = await supabase
    .from("clothing_items")
    .select("*")
    .eq("user_id", userId)
    .in("id", clothingItemIds)
    .returns<DbClothingItem[]>();

  if (itemError || !clothingItems || clothingItems.length === 0) {
    throw createHttpError(404, "Connected clothing item was not found");
  }

  const { data: clothingSizes, error: clothingSizeError } = await supabase
    .from("clothing_sizes")
    .select("*")
    .eq("user_id", userId)
    .in("clothing_item_id", clothingItemIds)
    .returns<DbMeasurementRow[]>();

  if (clothingSizeError || !clothingSizes || clothingSizes.length === 0) {
    throw createHttpError(404, "Reference clothing measurements were not found");
  }

  const { data: externalProduct, error: productError } = await supabase
    .from("external_products")
    .select("*")
    .eq("id", externalProductId)
    .eq("user_id", userId)
    .single<DbExternalProduct>();

  if (productError || !externalProduct) {
    throw createHttpError(404, "External product was not found");
  }

  const incompatibleReference = referenceClothing.find(
    (reference) =>
      !areCategoriesCompatible(reference.category as Category, externalProduct.category as Category)
  );
  if (incompatibleReference) {
    throw createHttpError(400, "Reference clothing category is not compatible with external product category");
  }

  const { data: externalSizes, error: sizesError } = await supabase
    .from("external_product_sizes")
    .select("*")
    .eq("external_product_id", externalProductId)
    .eq("user_id", userId)
    .returns<DbExternalProductSize[]>();

  if (sizesError || !externalSizes || externalSizes.length === 0) {
    throw createHttpError(404, "External product sizes were not found");
  }

  const referenceInput: ReferenceClothingInput[] = referenceClothing.map((reference) => {
    const clothingItem = clothingItems.find((item) => item.id === reference.clothing_item_id);
    const clothingSize = clothingSizes.find((size) => size.clothing_item_id === reference.clothing_item_id);
    if (!clothingItem || !clothingSize) {
      throw createHttpError(404, "Reference clothing measurements were not found");
    }
    return {
      id: reference.id,
      clothingItemId: clothingItem.id,
      sizeLabel: clothingItem.size_label,
      fitType: reference.fit_type,
      preferenceScore: reference.preference_score ?? 100,
      measurements: rowToMeasurements(clothingSize)
    };
  });

  const sizeInputs: ExternalProductSizeInput[] = externalSizes.map((size) => ({
    id: size.id,
    sizeLabel: size.size_label,
    fitType: externalProduct.fit_type,
    measurements: rowToMeasurements(size),
    measurementQuality: {
      measurementSource: size.measurement_source,
      parsingStatus: size.parsing_status,
      extractionConfidence: size.extraction_confidence
    }
  }));

  const feedbackProfile = await buildUserFeedbackFitProfile(
    userId,
    externalProduct.category as Category
  );

  const recommendation = recommendBestSizeWithReferences(
    referenceInput,
    sizeInputs,
    externalProduct.category as Category,
    feedbackProfile
  );
  const best = recommendation.recommended;

  return {
    response: {
      recommendedSize: best.sizeLabel,
      fitScore: best.finalFitScore,
      fitLabel: best.fitLabel,
      fitComment: best.fitComment,
      recommendationConfidence: best.recommendationConfidence,
      diff: best.diffs,
      partExplanations: best.partExplanations,
      partStatuses: best.partStatuses,
      scoreExplanation: best.scoreExplanation,
      confidenceBreakdown: best.confidenceBreakdown,
      baseWeights: recommendation.baseWeights,
      dynamicWeights: recommendation.dynamicWeights,
      referenceVariance: recommendation.referenceVariance,
      weightingStrategy: recommendation.weightingStrategy,
      referenceProfile: recommendation.referenceProfile,
      feedbackProfile: recommendation.feedbackProfile,
      allSizeScores: recommendation.allSizeScores.map((score) => ({
        externalProductSizeId: score.externalProductSizeId,
        sizeLabel: score.sizeLabel,
        fitScore: score.finalFitScore,
        fitLabel: score.fitLabel,
        weightedFitDistance: score.weightedFitDistance,
        recommendationConfidence: score.recommendationConfidence,
        scoreExplanation: score.scoreExplanation,
        confidenceBreakdown: score.confidenceBreakdown
      })),
      algorithmVersion: ALGORITHM_VERSION
    },
    persistence: {
      referenceClothingId: referenceInput[0].id,
      externalProductId: externalProduct.id,
      recommendedExternalProductSizeId: best.externalProductSizeId,
      recommendedSizeLabel: best.sizeLabel,
      fitScore: best.finalFitScore,
      fitLabel: best.fitLabel,
      fitComment: best.fitComment,
      weightedFitDistance: best.weightedFitDistance,
      algorithmVersion: ALGORITHM_VERSION,
      recommendationConfidence: best.recommendationConfidence,
      resultDetails: {
        baseWeights: recommendation.baseWeights,
        dynamicWeights: recommendation.dynamicWeights,
        referenceVariance: recommendation.referenceVariance,
        weightingStrategy: recommendation.weightingStrategy,
        referenceProfile: recommendation.referenceProfile,
        feedbackProfile: recommendation.feedbackProfile,
        diffs: best.diffs,
        partExplanations: best.partExplanations,
        partStatuses: best.partStatuses,
        scoreExplanation: best.scoreExplanation,
        confidenceBreakdown: best.confidenceBreakdown,
        referenceClothingIds: referenceInput.map((reference) => reference.id),
        allSizeScores: recommendation.allSizeScores
      }
    }
  };
};

export const listRecentFitAnalysisResults = async (userId: string): Promise<FitAnalysisResultRow[]> => {
  const { data, error } = await supabase
    .from("fit_analysis_results")
    .select("*")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(20)
    .returns<FitAnalysisResultRow[]>();
  if (error) throw createHttpError(500, "Failed to load recent fit analysis results");
  return data ?? [];
};

export const getFitAnalysisResult = async (
  userId: string,
  id: string
): Promise<FitAnalysisResultRow> => {
  const { data, error } = await supabase
    .from("fit_analysis_results")
    .select("*")
    .eq("user_id", userId)
    .eq("id", id)
    .single<FitAnalysisResultRow>();
  if (error || !data) throw createHttpError(404, "Fit analysis result was not found");
  return data;
};

export const replayFitRecommendation = (result: FitAnalysisResultRow): FitRecommendationResult => {
  const details = asRecord(result.result_details);
  return {
    fitAnalysisResultId: result.id,
    recommendedSize: result.recommended_size_label,
    fitScore: result.fit_score,
    fitLabel: result.fit_label as FitRecommendationResult["fitLabel"],
    fitComment: result.fit_comment,
    recommendationConfidence: result.recommendation_confidence as FitRecommendationResult["recommendationConfidence"],
    diff: asRecord(details.diffs) as FitRecommendationResult["diff"],
    partExplanations: asStringArray(details.partExplanations),
    partStatuses: asRecord(details.partStatuses) as FitRecommendationResult["partStatuses"],
    scoreExplanation: details.scoreExplanation as FitRecommendationResult["scoreExplanation"],
    confidenceBreakdown: details.confidenceBreakdown as FitRecommendationResult["confidenceBreakdown"],
    baseWeights: asRecord(details.baseWeights) as FitRecommendationResult["baseWeights"],
    dynamicWeights: asRecord(details.dynamicWeights) as FitRecommendationResult["dynamicWeights"],
    referenceVariance: asRecord(details.referenceVariance) as FitRecommendationResult["referenceVariance"],
    weightingStrategy: (details.weightingStrategy as FitRecommendationResult["weightingStrategy"]) ?? "base_static",
    referenceProfile: details.referenceProfile as FitRecommendationResult["referenceProfile"],
    feedbackProfile: details.feedbackProfile as FitRecommendationResult["feedbackProfile"],
    allSizeScores: (Array.isArray(details.allSizeScores) ? details.allSizeScores : []) as FitRecommendationResult["allSizeScores"],
    algorithmVersion: result.algorithm_version
  };
};

export const deleteFitAnalysisResultForUser = async (
  userId: string,
  id: string
): Promise<void> => {
  const { error } = await supabase
    .from("fit_analysis_results")
    .delete()
    .eq("user_id", userId)
    .eq("id", id);
  if (error) throw createHttpError(500, "Failed to roll back incomplete fit analysis");
};
