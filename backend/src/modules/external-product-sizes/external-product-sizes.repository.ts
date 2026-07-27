import { supabase } from "../../config/supabase";
import type { ExternalProductSizeRow, JsonObject, MeasurementMap } from "../../shared/types/database";
import { createHttpError } from "../../shared/utils/http-error";
import {
  isMissingOutseamColumnError,
  toLegacyMeasurementStorage
} from "../../shared/utils/measurements";

export interface ExternalProductSizeDto extends MeasurementMap {
  size_label: string;
  raw_size_data: JsonObject;
  parsing_status: string | null;
  measurement_source: string | null;
  extracted_text: string | null;
  extraction_confidence: number | null;
}

export const insertExternalProductSize = async (
  userId: string,
  externalProductId: string,
  dto: ExternalProductSizeDto
): Promise<ExternalProductSizeRow> => {
  const payload = { ...dto, user_id: userId, external_product_id: externalProductId };
  let response = await supabase
    .from("external_product_sizes")
    .insert(payload)
    .select("*")
    .single<ExternalProductSizeRow>();
  if (isMissingOutseamColumnError(response.error)) {
    response = await supabase
      .from("external_product_sizes")
      .insert(toLegacyMeasurementStorage(payload))
      .select("*")
      .single<ExternalProductSizeRow>();
  }
  const { data, error } = response;
  if (error || !data) throw createHttpError(500, "Failed to create external product size");
  return data;
};

export const selectExternalProductSizes = async (
  userId: string,
  externalProductId: string
): Promise<ExternalProductSizeRow[]> => {
  const { data, error } = await supabase
    .from("external_product_sizes")
    .select("*")
    .eq("user_id", userId)
    .eq("external_product_id", externalProductId)
    .order("size_label", { ascending: true })
    .returns<ExternalProductSizeRow[]>();
  if (error) throw createHttpError(500, "Failed to load external product sizes");
  return data ?? [];
};

export const patchExternalProductSize = async (
  userId: string,
  id: string,
  dto: Partial<ExternalProductSizeDto>
): Promise<ExternalProductSizeRow> => {
  const { data, error } = await supabase
    .from("external_product_sizes")
    .update({ ...dto, updated_at: new Date().toISOString() })
    .eq("user_id", userId)
    .eq("id", id)
    .select("*")
    .single<ExternalProductSizeRow>();
  if (error || !data) throw createHttpError(500, "Failed to update external product size");
  return data;
};

export const removeExternalProductSize = async (userId: string, id: string): Promise<void> => {
  const { error } = await supabase.from("external_product_sizes").delete().eq("user_id", userId).eq("id", id);
  if (error) throw createHttpError(500, "Failed to delete external product size");
};
