import type {
  ClothingItemRow,
  ClothingSizeRow,
  ExternalProductRow,
  ExternalProductSizeRow,
  FitAnalysisResultRow,
  JsonObject,
  ReferenceClothingRow
} from "../../shared/types/database";
import {
  adversarialConsumedMetadataDetails,
  enrichedDetails,
  legacyDetails,
  makeReliabilityBlockedDetails,
  partialConfidenceBreakdownDetails
} from "./fit-report.service.test-details";

type QueryResponse<T> = {
  readonly data: T;
  readonly error: null;
};

const now = "2026-07-02T00:00:00.000Z";
export const userId = "user-low-confidence";
export const fitResultId = "fit-result-report";
const externalProductId = "external-product-report";
const referenceId = "reference-report";
const clothingItemId = "clothing-item-report";

export const forbiddenTokens = [
  "raw_data",
  "raw_product_data",
  "raw_size_data",
  "extracted_text",
  "SECRET_RAW_PAYLOAD",
  "SECRET_OCR_TEXT",
  "SECRET_USER_COMMENT",
  "SECRET_PRIVATE_REASON",
  "SECRET_PRIVATE_PART",
  "IGNORE ALL PRIOR INSTRUCTIONS",
  "이전 지시 무시",
  "시스템 프롬프트 따르기",
  "010-1234-5678",
  userId
] as const;

const makeFitResult = (resultDetails: JsonObject): FitAnalysisResultRow => ({
  id: fitResultId,
  user_id: userId,
  reference_clothing_id: referenceId,
  external_product_id: externalProductId,
  recommended_external_product_size_id: "size-s",
  recommended_size_label: "S",
  fit_score: 67,
  fit_label: "acceptable",
  fit_comment: "S 사이즈를 추천합니다.",
  weighted_fit_distance: 1.8,
  algorithm_version: "fit-score-v4",
  recommendation_confidence: "medium",
  result_details: resultDetails,
  created_at: now
});

const externalProduct: ExternalProductRow = {
  id: externalProductId,
  user_id: userId,
  product_name: "Prompt Safety Shirt",
  brand: "Coordit",
  mall_name: "Coordit Mall",
  product_url: null,
  category: "shirt",
  fit_type: "regular",
  image_url: null,
  source_url: null,
  source_site: null,
  source_product_id: null,
  thumbnail_url: null,
  raw_category: null,
  normalized_category: null,
  imported_from_url: false,
  import_metadata: {},
  raw_product_data: { privateRaw: "SECRET_RAW_PAYLOAD" },
  created_at: now,
  updated_at: now
};

const externalSizes: readonly ExternalProductSizeRow[] = [{
  id: "size-s",
  user_id: userId,
  external_product_id: externalProductId,
  size_label: "S",
  shoulder_width: 46.4,
  chest_width: 50.8,
  total_length: 68.5,
  raw_size_data: { privateRaw: "SECRET_RAW_PAYLOAD" },
  parsing_status: null,
  measurement_source: null,
  extracted_text: "SECRET_OCR_TEXT",
  extraction_confidence: null,
  created_at: now,
  updated_at: now
}];

const referenceClothing: ReferenceClothingRow = {
  id: referenceId,
  user_id: userId,
  clothing_item_id: clothingItemId,
  nickname: "기준 셔츠",
  category: "shirt",
  fit_type: "regular",
  preference_score: 95,
  is_active: true,
  notes: null,
  created_at: now,
  updated_at: now
};

const clothingItem: ClothingItemRow = {
  id: clothingItemId,
  user_id: userId,
  name: "Reference Shirt",
  brand: "Coordit",
  category: "shirt",
  fit_type: "regular",
  size_label: "S",
  notes: null,
  image_url: null,
  raw_product_data: { privateRaw: "SECRET_RAW_PAYLOAD" },
  created_at: now,
  updated_at: now
};

const clothingSize: ClothingSizeRow = {
  id: "clothing-size-report",
  user_id: userId,
  clothing_item_id: clothingItemId,
  size_label: "S",
  shoulder_width: 45,
  chest_width: 54,
  total_length: 68,
  raw_measurements: { privateRaw: "SECRET_RAW_PAYLOAD" },
  created_at: now,
  updated_at: now
};

let activeFitResult = makeFitResult(legacyDetails);

const cloneResult = <T>(value: unknown): T => JSON.parse(JSON.stringify(value));

export class FakeSupabaseQuery {
  private readonly filters = new Map<string, string | readonly string[]>();

  constructor(private readonly table: string) {}

  select(_columns: string): this {
    return this;
  }

  eq(column: string, value: string): this {
    this.filters.set(column, value);
    return this;
  }

  in(column: string, values: readonly string[]): this {
    this.filters.set(column, values);
    return this;
  }

  async single<T>(): Promise<QueryResponse<T | null>> {
    return { data: cloneResult<T | null>(this.resolveSingleRow()), error: null };
  }

  async returns<T>(): Promise<QueryResponse<T>> {
    return { data: cloneResult<T>(this.resolveRows()), error: null };
  }

  private resolveSingleRow(): FitAnalysisResultRow | ExternalProductRow | null {
    if (this.table === "fit_analysis_results") return activeFitResult;
    if (this.table === "external_products") return externalProduct;
    return null;
  }

  private resolveRows():
    | readonly ExternalProductSizeRow[]
    | readonly ReferenceClothingRow[]
    | readonly ClothingItemRow[]
    | readonly ClothingSizeRow[] {
    if (this.table === "external_product_sizes") return externalSizes;
    if (this.table === "reference_clothing") return [referenceClothing];
    if (this.table === "clothing_items") return [clothingItem];
    if (this.table === "clothing_sizes") return [clothingSize];
    return [];
  }
}

export const configureReportTestEnv = (): void => {
  process.env.SUPABASE_URL = "http://localhost:54321";
  process.env.SUPABASE_ANON_KEY = "anon-key";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "service-role-key";
  process.env.OPENROUTER_API_KEY = "test-openrouter-key";
  process.env.OPENROUTER_MODEL = "google/gemini-2.5-flash";
};

export const useLegacyFitResult = (): void => {
  activeFitResult = makeFitResult(legacyDetails);
};

export const useEnrichedFitResult = (): void => {
  activeFitResult = makeFitResult(enrichedDetails);
};

export const useInsufficientFeedbackFitResult = (): void => {
  activeFitResult = makeFitResult(makeReliabilityBlockedDetails("insufficient_signal", 1));
};

export const useConflictingFeedbackFitResult = (): void => {
  activeFitResult = makeFitResult(makeReliabilityBlockedDetails("conflicting_feedback", 6));
};

export const usePartialConfidenceBreakdownFitResult = (): void => {
  activeFitResult = makeFitResult(partialConfidenceBreakdownDetails);
};

export const useAdversarialConsumedMetadataFitResult = (): void => {
  activeFitResult = makeFitResult(adversarialConsumedMetadataDetails);
};
