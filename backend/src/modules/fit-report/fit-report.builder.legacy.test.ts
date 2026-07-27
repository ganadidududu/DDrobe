import assert from "node:assert/strict";
import type {
  ClothingItemRow,
  ClothingSizeRow,
  ExternalProductRow,
  ExternalProductSizeRow,
  FitAnalysisResultRow,
  ReferenceClothingRow
} from "../../shared/types/database";

type QueryResponse<T> = {
  readonly data: T;
  readonly error: null;
};

const now = "2026-07-02T00:00:00.000Z";
const userId = "user-legacy-report";
const fitResultId = "fit-result-legacy";
const externalProductId = "external-product-legacy";
const referenceId = "reference-legacy";
const clothingItemId = "clothing-item-legacy";

const fitResult: FitAnalysisResultRow = {
  id: fitResultId,
  user_id: userId,
  reference_clothing_id: referenceId,
  external_product_id: externalProductId,
  recommended_external_product_size_id: "size-m",
  recommended_size_label: "M",
  fit_score: 94,
  fit_label: "good_fit",
  fit_comment: "M 사이즈를 추천합니다.",
  weighted_fit_distance: 0.7,
  algorithm_version: "fit-score-v3",
  recommendation_confidence: "high",
  result_details: {
    referenceProfile: {
      measurements: {
        shoulder_width: 50,
        chest_width: 60,
        total_length: 70,
        sleeve_length: 62
      },
      tolerances: {
        shoulder_width: 1,
        chest_width: 1.5,
        total_length: 2,
        sleeve_length: 1.5
      }
    },
    dynamicWeights: {
      shoulder_width: 0.3,
      chest_width: 0.3,
      total_length: 0.2,
      sleeve_length: 0.2
    },
    weightingStrategy: "reference_profile_v1",
    referenceClothingIds: [referenceId],
    allSizeScores: [
      {
        sizeLabel: "M",
        finalFitScore: 94,
        fitLabel: "good_fit",
        weightedFitDistance: 0.7,
        recommendationConfidence: "high"
      },
      {
        sizeLabel: "L",
        finalFitScore: 86,
        fitLabel: "acceptable",
        weightedFitDistance: 1.4,
        recommendationConfidence: "medium"
      }
    ]
  },
  created_at: now
};

const externalProduct: ExternalProductRow = {
  id: externalProductId,
  user_id: userId,
  product_name: "Legacy Hoodie",
  brand: "Coordit",
  mall_name: "Coordit Mall",
  product_url: null,
  category: "hoodie",
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
  raw_product_data: {},
  created_at: now,
  updated_at: now
};

const externalSizes: readonly ExternalProductSizeRow[] = [
  {
    id: "size-m",
    user_id: userId,
    external_product_id: externalProductId,
    size_label: "M",
    shoulder_width: 50.4,
    chest_width: 60.8,
    total_length: 70.5,
    sleeve_length: 62.2,
    raw_size_data: {},
    parsing_status: null,
    measurement_source: null,
    extracted_text: null,
    extraction_confidence: null,
    created_at: now,
    updated_at: now
  },
  {
    id: "size-l",
    user_id: userId,
    external_product_id: externalProductId,
    size_label: "L",
    shoulder_width: 53,
    chest_width: 64,
    total_length: 73,
    sleeve_length: 64,
    raw_size_data: {},
    parsing_status: null,
    measurement_source: null,
    extracted_text: null,
    extraction_confidence: null,
    created_at: now,
    updated_at: now
  }
];

const referenceClothing: ReferenceClothingRow = {
  id: referenceId,
  user_id: userId,
  clothing_item_id: clothingItemId,
  nickname: "좋아하는 후디",
  category: "hoodie",
  fit_type: "regular",
  preference_score: 100,
  is_active: true,
  notes: null,
  created_at: now,
  updated_at: now
};

const clothingItem: ClothingItemRow = {
  id: clothingItemId,
  user_id: userId,
  name: "Reference Hoodie",
  brand: "Coordit",
  category: "hoodie",
  fit_type: "regular",
  size_label: "M",
  notes: null,
  image_url: null,
  raw_product_data: {},
  created_at: now,
  updated_at: now
};

const clothingSize: ClothingSizeRow = {
  id: "clothing-size-legacy",
  user_id: userId,
  clothing_item_id: clothingItemId,
  size_label: "M",
  shoulder_width: 50,
  chest_width: 60,
  total_length: 70,
  sleeve_length: 62,
  raw_measurements: {},
  created_at: now,
  updated_at: now
};

const cloneResult = <T>(value: unknown): T => JSON.parse(JSON.stringify(value));

class FakeSupabaseQuery {
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
    if (this.table === "fit_analysis_results") {
      return this.filters.get("id") === fitResultId ? fitResult : null;
    }
    if (this.table === "external_products") {
      return this.filters.get("id") === externalProductId ? externalProduct : null;
    }
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

const main = async (): Promise<void> => {
  process.env.SUPABASE_URL = "http://localhost:54321";
  process.env.SUPABASE_ANON_KEY = "anon-key";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "service-role-key";

  const [{ supabase }, { buildFitReportInput }] = await Promise.all([
    import("../../config/supabase"),
    import("./fit-report.builder")
  ]);

  Object.defineProperty(supabase, "from", {
    value: (table: string): FakeSupabaseQuery => new FakeSupabaseQuery(table)
  });

  const reportInput = await buildFitReportInput(userId, fitResultId);

  assert.equal(reportInput.recommendation.recommendedSize, "M");
  assert.equal(reportInput.recommendation.scoreGapToSecond, 8);
  assert.equal(reportInput.explanation.missingMeasurementSummary.summary, "unavailable");
  assert.equal(reportInput.explanation.dataQualitySummary.summary, "unavailable");
  assert.equal(reportInput.explanation.confidenceReasons.length, 0);
  assert.equal(reportInput.sizeScores.length, 2);
  assert.equal(reportInput.measurements.length, 4);
  assert.equal(reportInput.referenceClothingSummary[0]?.name, "좋아하는 후디");

  console.log("legacy result_details report-builder compatibility passed");
};

main().catch((error: unknown) => {
  if (error instanceof Error) {
    console.error(error.message);
  }
  throw error;
});
