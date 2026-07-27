import { supabase } from "../../config/supabase";
import type { Category, ExternalProductRow, FitType, JsonObject } from "../../shared/types/database";
import { createHttpError } from "../../shared/utils/http-error";

export interface ExternalProductDto {
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
}

export const insertExternalProduct = async (userId: string, dto: ExternalProductDto): Promise<ExternalProductRow> => {
  const { data, error } = await supabase
    .from("external_products")
    .insert({ ...dto, user_id: userId })
    .select("*")
    .single<ExternalProductRow>();
  if (error || !data) throw createHttpError(500, "Failed to create external product");
  return data;
};

export const selectExternalProducts = async (userId: string): Promise<ExternalProductRow[]> => {
  const { data, error } = await supabase
    .from("external_products")
    .select("*")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .returns<ExternalProductRow[]>();
  if (error) throw createHttpError(500, "Failed to load external products");
  return data ?? [];
};

export const selectExternalProductById = async (userId: string, id: string): Promise<ExternalProductRow> => {
  const { data, error } = await supabase
    .from("external_products")
    .select("*")
    .eq("user_id", userId)
    .eq("id", id)
    .single<ExternalProductRow>();
  if (error || !data) throw createHttpError(404, "External product was not found");
  return data;
};

export const patchExternalProduct = async (
  userId: string,
  id: string,
  dto: Partial<ExternalProductDto>
): Promise<ExternalProductRow> => {
  const { data, error } = await supabase
    .from("external_products")
    .update({ ...dto, updated_at: new Date().toISOString() })
    .eq("user_id", userId)
    .eq("id", id)
    .select("*")
    .single<ExternalProductRow>();
  if (error || !data) throw createHttpError(500, "Failed to update external product");
  return data;
};
