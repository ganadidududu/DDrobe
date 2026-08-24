import { supabase } from "../../config/supabase";
import type {
  Category,
  ExternalProductRow,
  ExternalProductSizeRow,
  FitAnalysisResultRow,
  FitType,
  MeasurementMap,
  ReferenceClothingRow
} from "../../shared/types/database";
import { createHttpError } from "../../shared/utils/http-error";
import { rowToMeasurements } from "../../shared/utils/measurements";
import { readStoredFitReport, storeFitReport } from "./fit-report.artifact";
import type { GenerateFitReportResult, ReferenceClothingReportSummary } from "./fit-report.types";

interface ClothingItemForReport {
  readonly id: string;
  readonly name: string;
  readonly category: Category;
  readonly fit_type: FitType;
  readonly size_label: string | null;
}

interface ClothingSizeForReport extends MeasurementMap {
  readonly clothing_item_id: string;
}

export const loadFitResult = async (
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

export const loadPersistedFitReport = async (
  userId: string,
  fitAnalysisResultId: string
): Promise<Omit<GenerateFitReportResult, "availableThreads"> | null> => {
  const fitResult = await loadFitResult(userId, fitAnalysisResultId);
  const stored = readStoredFitReport(fitResult.result_details);
  if (!stored) return null;
  return {
    fitAnalysisResultId,
    source: stored.source,
    modelName: stored.modelName,
    promptVersion: stored.promptVersion,
    report: stored.report,
    chartData: stored.chartData
  };
};

export const persistFitReport = async (
  userId: string,
  fitResult: FitAnalysisResultRow,
  report: GenerateFitReportResult
): Promise<void> => {
  const { error } = await supabase
    .from("fit_analysis_results")
    .update({ result_details: storeFitReport(fitResult.result_details, report) })
    .eq("user_id", userId)
    .eq("id", fitResult.id)
    .select("id")
    .single<{ id: string }>();

  if (error) throw createHttpError(500, "Failed to save fit report");
};

export const loadExternalProduct = async (
  userId: string,
  id: string
): Promise<ExternalProductRow> => {
  const { data, error } = await supabase
    .from("external_products")
    .select("*")
    .eq("user_id", userId)
    .eq("id", id)
    .single<ExternalProductRow>();

  if (error || !data) throw createHttpError(404, "External product was not found");
  return data;
};

export const loadExternalProductSizes = async (
  userId: string,
  externalProductId: string
): Promise<ExternalProductSizeRow[]> => {
  const { data, error } = await supabase
    .from("external_product_sizes")
    .select("*")
    .eq("user_id", userId)
    .eq("external_product_id", externalProductId)
    .returns<ExternalProductSizeRow[]>();

  if (error) throw createHttpError(500, "Failed to load external product sizes");
  return data ?? [];
};

const loadReferenceClothing = async (
  userId: string,
  ids: readonly string[]
): Promise<ReferenceClothingRow[]> => {
  const { data, error } = await supabase
    .from("reference_clothing")
    .select("*")
    .eq("user_id", userId)
    .in("id", ids)
    .returns<ReferenceClothingRow[]>();

  if (error) throw createHttpError(500, "Failed to load reference clothing");
  return data ?? [];
};

const loadClothingItems = async (
  userId: string,
  ids: readonly string[]
): Promise<ClothingItemForReport[]> => {
  if (ids.length === 0) return [];
  const { data, error } = await supabase
    .from("clothing_items")
    .select("id, name, category, fit_type, size_label")
    .eq("user_id", userId)
    .in("id", ids)
    .returns<ClothingItemForReport[]>();

  if (error) throw createHttpError(500, "Failed to load clothing items");
  return data ?? [];
};

const loadClothingSizes = async (
  userId: string,
  clothingItemIds: readonly string[]
): Promise<ClothingSizeForReport[]> => {
  if (clothingItemIds.length === 0) return [];
  const { data, error } = await supabase
    .from("clothing_sizes")
    .select("*")
    .eq("user_id", userId)
    .in("clothing_item_id", clothingItemIds)
    .returns<ClothingSizeForReport[]>();

  if (error) throw createHttpError(500, "Failed to load clothing measurements");
  return data ?? [];
};

export const buildReferenceSummary = async (
  userId: string,
  referenceIds: readonly string[]
): Promise<ReferenceClothingReportSummary[]> => {
  const references = await loadReferenceClothing(userId, referenceIds);
  const clothingItemIds = references.map((reference) => reference.clothing_item_id);
  const clothingItems = await loadClothingItems(userId, clothingItemIds);
  const clothingSizes = await loadClothingSizes(userId, clothingItemIds);

  return references.map((reference) => {
    const item = clothingItems.find((candidate) => candidate.id === reference.clothing_item_id);
    const size = clothingSizes.find(
      (candidate) => candidate.clothing_item_id === reference.clothing_item_id
    );
    return {
      name: reference.nickname || item?.name || "기준 의류",
      category: reference.category,
      fitType: reference.fit_type,
      sizeLabel: item?.size_label ?? null,
      preferenceScore: reference.preference_score,
      measurements: size ? rowToMeasurements(size) : {}
    };
  });
};
