export type JsonObject = Record<string, unknown>;

export type Category =
  | "tshirt"
  | "shirt"
  | "sweatshirt"
  | "hoodie"
  | "knit"
  | "jacket"
  | "coat"
  | "pants"
  | "jeans"
  | "shorts"
  | "skirt";

export type FitType = "slim" | "regular" | "relaxed" | "oversized";

export type MeasurementKey =
  | "total_length"
  | "shoulder_width"
  | "chest_width"
  | "sleeve_length"
  | "waist_width"
  | "hip_width"
  | "rise"
  | "outseam";

export type MeasurementMap = Partial<Record<MeasurementKey, number | null>>;

export interface UserRow {
  id: string;
  email: string;
  display_name: string | null;
  gender: string | null;
  birth_date: string | null;
  birth_year: number | null;
  created_at: string;
  updated_at: string;
}

export interface ConsentVersionRow {
  readonly key: string;
  readonly version: string;
  readonly title: string;
  readonly description: string | null;
  readonly required: boolean;
  readonly effective_from: string;
  readonly created_at: string;
}

export interface UserConsentRow {
  readonly id: string;
  readonly user_id: string;
  readonly consent_key: string;
  readonly consent_version: string;
  readonly accepted: boolean;
  readonly accepted_at: string | null;
  readonly revoked_at: string | null;
  readonly required: boolean;
  readonly ip_address: string | null;
  readonly user_agent: string | null;
  readonly created_at: string;
  readonly updated_at: string;
}

export interface ClothingItemRow {
  id: string;
  user_id: string;
  name: string;
  brand: string | null;
  category: Category;
  fit_type: FitType;
  size_label: string | null;
  notes: string | null;
  image_url: string | null;
  raw_product_data: JsonObject;
  created_at: string;
  updated_at: string;
}

export interface ClothingSizeRow extends MeasurementMap {
  id: string;
  user_id: string;
  clothing_item_id: string;
  size_label: string | null;
  raw_measurements: JsonObject;
  created_at: string;
  updated_at: string;
}

export interface ReferenceClothingRow {
  id: string;
  user_id: string;
  clothing_item_id: string;
  nickname: string | null;
  category: Category;
  fit_type: FitType;
  preference_score: number;
  is_active: boolean;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

export interface ExternalProductRow {
  id: string;
  user_id: string;
  product_name: string;
  brand: string | null;
  mall_name: string | null;
  product_url: string | null;
  category: Category;
  fit_type: FitType;
  image_url: string | null;
  source_url: string | null;
  source_site: string | null;
  source_product_id: string | null;
  thumbnail_url: string | null;
  raw_category: string | null;
  normalized_category: string | null;
  imported_from_url: boolean;
  import_metadata: JsonObject;
  raw_product_data: JsonObject;
  created_at: string;
  updated_at: string;
}

export interface ExternalProductSizeRow extends MeasurementMap {
  id: string;
  user_id: string;
  external_product_id: string;
  size_label: string;
  raw_size_data: JsonObject;
  parsing_status: string | null;
  measurement_source: string | null;
  extracted_text: string | null;
  extraction_confidence: number | null;
  created_at: string;
  updated_at: string;
}

export interface FitAnalysisResultRow {
  id: string;
  user_id: string;
  reference_clothing_id: string;
  external_product_id: string;
  recommended_external_product_size_id: string | null;
  recommended_size_label: string;
  fit_score: number;
  fit_label: string;
  fit_comment: string;
  weighted_fit_distance: number;
  algorithm_version: string;
  recommendation_confidence: string;
  result_details: JsonObject;
  created_at: string;
}

export interface UserFeedbackRow {
  id: string;
  user_id: string;
  fit_analysis_result_id: string;
  purchased_size_label: string | null;
  actual_fit_rating: number | null;
  actual_fit_label: string | null;
  part_feedback: JsonObject;
  comment: string | null;
  raw_data: JsonObject;
  created_at: string;
}
