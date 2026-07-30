import { supabase } from "../../config/supabase";
import type { ClothingItemRow } from "../../shared/types/database";
import { createHttpError } from "../../shared/utils/http-error";
import type { CreateClothingItemDto, UpdateClothingItemDto } from "./clothing-items.types";
import type { ClothingSizeDto } from "../clothing-sizes/clothing-sizes.repository";

interface ClothingItemWithSizeRow {
  clothingItem: ClothingItemRow;
  clothingSize: import("../../shared/types/database").ClothingSizeRow;
}

export const insertClothingItem = async (
  userId: string,
  dto: CreateClothingItemDto
): Promise<ClothingItemRow> => {
  const { data, error } = await supabase
    .from("clothing_items")
    .insert({ ...dto, user_id: userId })
    .select("*")
    .single<ClothingItemRow>();
  if (error || !data) throw createHttpError(500, "Failed to create clothing item");
  return data;
};

export const insertClothingItemWithSize = async (
  userId: string,
  clothingItem: CreateClothingItemDto,
  clothingSize: ClothingSizeDto,
  idempotencyKey: string
): Promise<ClothingItemWithSizeRow> => {
  const { data, error } = await supabase
    .rpc("create_clothing_item_with_size", {
      p_user_id: userId,
      p_item: clothingItem,
      p_size: clothingSize,
      p_idempotency_key: idempotencyKey
    })
    .single<ClothingItemWithSizeRow>();
  if (error || !data) throw createHttpError(500, "Failed to save clothing item and size");
  return data;
};

export const selectClothingItems = async (userId: string): Promise<ClothingItemRow[]> => {
  const { data, error } = await supabase
    .from("clothing_items")
    .select("*")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .returns<ClothingItemRow[]>();
  if (error) throw createHttpError(500, "Failed to load clothing items");
  return data ?? [];
};

export const selectClothingItemById = async (
  userId: string,
  id: string
): Promise<ClothingItemRow> => {
  const { data, error } = await supabase
    .from("clothing_items")
    .select("*")
    .eq("user_id", userId)
    .eq("id", id)
    .single<ClothingItemRow>();
  if (error || !data) throw createHttpError(404, "Clothing item was not found");
  return data;
};

export const patchClothingItem = async (
  userId: string,
  id: string,
  dto: UpdateClothingItemDto
): Promise<ClothingItemRow> => {
  const { data, error } = await supabase
    .from("clothing_items")
    .update({ ...dto, updated_at: new Date().toISOString() })
    .eq("user_id", userId)
    .eq("id", id)
    .select("*")
    .single<ClothingItemRow>();
  if (error || !data) throw createHttpError(500, "Failed to update clothing item");
  return data;
};

export const removeClothingItem = async (userId: string, id: string): Promise<void> => {
  const { data: references, error: referenceError } = await supabase
    .from("reference_clothing")
    .select("id")
    .eq("user_id", userId)
    .eq("clothing_item_id", id)
    .returns<Array<{ id: string }>>();
  if (referenceError) throw createHttpError(500, "Failed to load clothing references");

  const referenceIds = (references ?? []).map((reference) => reference.id);
  if (referenceIds.length > 0) {
    const { error: analysisError } = await supabase
      .from("fit_analysis_results")
      .delete()
      .eq("user_id", userId)
      .in("reference_clothing_id", referenceIds);
    if (analysisError) throw createHttpError(500, "Failed to delete clothing fit history");
  }

  const { error } = await supabase
    .from("clothing_items")
    .delete()
    .eq("user_id", userId)
    .eq("id", id);
  if (error) throw createHttpError(500, "Failed to delete clothing item");
};
