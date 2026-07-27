import { supabase } from "../../config/supabase";
import type { ClothingSizeRow, JsonObject, MeasurementMap } from "../../shared/types/database";
import { createHttpError } from "../../shared/utils/http-error";
import {
  isMissingOutseamColumnError,
  toLegacyMeasurementStorage
} from "../../shared/utils/measurements";

export interface ClothingSizeDto extends MeasurementMap {
  clothing_item_id?: string;
  size_label: string | null;
  raw_measurements: JsonObject;
}

export const insertClothingSize = async (
  userId: string,
  clothingItemId: string,
  dto: ClothingSizeDto
): Promise<ClothingSizeRow> => {
  const payload = { ...dto, user_id: userId, clothing_item_id: clothingItemId };
  let response = await supabase
    .from("clothing_sizes")
    .insert(payload)
    .select("*")
    .single<ClothingSizeRow>();
  if (isMissingOutseamColumnError(response.error)) {
    response = await supabase
      .from("clothing_sizes")
      .insert(toLegacyMeasurementStorage(payload))
      .select("*")
      .single<ClothingSizeRow>();
  }
  const { data, error } = response;
  if (error || !data) throw createHttpError(500, "Failed to create clothing size");
  return data;
};

export const selectClothingSizes = async (
  userId: string,
  clothingItemId: string
): Promise<ClothingSizeRow[]> => {
  const { data, error } = await supabase
    .from("clothing_sizes")
    .select("*")
    .eq("user_id", userId)
    .eq("clothing_item_id", clothingItemId)
    .order("created_at", { ascending: false })
    .returns<ClothingSizeRow[]>();
  if (error) throw createHttpError(500, "Failed to load clothing sizes");
  return data ?? [];
};

export const patchClothingSize = async (
  userId: string,
  id: string,
  dto: Partial<ClothingSizeDto>
): Promise<ClothingSizeRow> => {
  const { data, error } = await supabase
    .from("clothing_sizes")
    .update({ ...dto, updated_at: new Date().toISOString() })
    .eq("user_id", userId)
    .eq("id", id)
    .select("*")
    .single<ClothingSizeRow>();
  if (error || !data) throw createHttpError(500, "Failed to update clothing size");
  return data;
};

export const removeClothingSize = async (userId: string, id: string): Promise<void> => {
  const { error } = await supabase.from("clothing_sizes").delete().eq("user_id", userId).eq("id", id);
  if (error) throw createHttpError(500, "Failed to delete clothing size");
};
