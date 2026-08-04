import { pickMeasurements, rowToMeasurements } from "../../shared/utils/measurements";
import { asOptionalRecord, asOptionalString } from "../../shared/utils/request";
import {
  insertClothingSize,
  patchClothingSize,
  removeClothingSize,
  selectClothingSizes,
  type ClothingSizeDto
} from "./clothing-sizes.repository";

export const toClothingSizeDto = (body: Record<string, unknown>): ClothingSizeDto => ({
  size_label: asOptionalString(body.sizeLabel ?? body.size_label),
  raw_measurements: asOptionalRecord(body.rawMeasurements ?? body.raw_measurements),
  ...pickMeasurements(body)
});

export const createClothingSizeForUser = async (
  userId: string,
  clothingItemId: string,
  body: Record<string, unknown>
) => {
  const row = await insertClothingSize(userId, clothingItemId, toClothingSizeDto(body));
  return { ...row, ...rowToMeasurements(row) };
};

export const listClothingSizesForUser = async (userId: string, clothingItemId: string) => {
  const rows = await selectClothingSizes(userId, clothingItemId);
  return rows.map((row) => ({ ...row, ...rowToMeasurements(row) }));
};

export const updateClothingSizeForUser = (
  userId: string,
  id: string,
  body: Record<string, unknown>
) => patchClothingSize(userId, id, toClothingSizeDto(body));

export const deleteClothingSizeForUser = (userId: string, id: string) =>
  removeClothingSize(userId, id);
