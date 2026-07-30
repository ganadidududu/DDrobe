import type { ClothingItemRow } from "../../shared/types/database";
import { asOptionalRecord, asOptionalString, asRequiredString } from "../../shared/utils/request";
import { createHttpError } from "../../shared/utils/http-error";
import {
  insertClothingItem,
  insertClothingItemWithSize,
  patchClothingItem,
  removeClothingItem,
  selectClothingItemById,
  selectClothingItems
} from "./clothing-items.repository";
import type { CreateClothingItemDto, UpdateClothingItemDto } from "./clothing-items.types";
import { toClothingSizeDto } from "../clothing-sizes/clothing-sizes.service";

const asIdempotencyKey = (value: unknown): string => {
  const key = asRequiredString(value, "idempotencyKey");
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(key)) {
    throw createHttpError(400, "A valid idempotencyKey is required");
  }
  return key;
};

const toCreateDto = (body: Record<string, unknown>): CreateClothingItemDto => ({
  name: asRequiredString(body.name, "name"),
  brand: asOptionalString(body.brand),
  category: asRequiredString(body.category, "category") as CreateClothingItemDto["category"],
  fit_type: (asOptionalString(body.fitType ?? body.fit_type) ?? "regular") as CreateClothingItemDto["fit_type"],
  size_label: asOptionalString(body.sizeLabel ?? body.size_label),
  notes: asOptionalString(body.notes),
  image_url: asOptionalString(body.imageUrl ?? body.image_url),
  raw_product_data: asOptionalRecord(body.rawProductData ?? body.raw_product_data)
});

const toUpdateDto = (body: Record<string, unknown>): UpdateClothingItemDto => {
  const dto: UpdateClothingItemDto = {};
  if ("name" in body) dto.name = asRequiredString(body.name, "name");
  if ("brand" in body) dto.brand = asOptionalString(body.brand);
  if ("category" in body) dto.category = asRequiredString(body.category, "category") as UpdateClothingItemDto["category"];
  if ("fitType" in body || "fit_type" in body) dto.fit_type = (asOptionalString(body.fitType ?? body.fit_type) ?? "regular") as UpdateClothingItemDto["fit_type"];
  if ("sizeLabel" in body || "size_label" in body) dto.size_label = asOptionalString(body.sizeLabel ?? body.size_label);
  if ("notes" in body) dto.notes = asOptionalString(body.notes);
  if ("imageUrl" in body || "image_url" in body) dto.image_url = asOptionalString(body.imageUrl ?? body.image_url);
  if ("rawProductData" in body || "raw_product_data" in body) dto.raw_product_data = asOptionalRecord(body.rawProductData ?? body.raw_product_data);
  return dto;
};

export const createClothingItemForUser = (userId: string, body: Record<string, unknown>) =>
  insertClothingItem(userId, toCreateDto(body));

export const createClothingItemWithSizeForUser = (userId: string, body: Record<string, unknown>) =>
  insertClothingItemWithSize(
    userId,
    toCreateDto(asOptionalRecord(body.item)),
    toClothingSizeDto(asOptionalRecord(body.size)),
    asIdempotencyKey(body.idempotencyKey)
  );

export const listClothingItemsForUser = (userId: string): Promise<ClothingItemRow[]> =>
  selectClothingItems(userId);

export const getClothingItemForUser = (userId: string, id: string): Promise<ClothingItemRow> =>
  selectClothingItemById(userId, id);

export const updateClothingItemForUser = (
  userId: string,
  id: string,
  body: Record<string, unknown>
) => patchClothingItem(userId, id, toUpdateDto(body));

export const deleteClothingItemForUser = (userId: string, id: string): Promise<void> =>
  removeClothingItem(userId, id);
