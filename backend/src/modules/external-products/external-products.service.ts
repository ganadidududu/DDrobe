import { asOptionalRecord, asOptionalString, asRequiredString } from "../../shared/utils/request";
import {
  insertExternalProduct,
  patchExternalProduct,
  selectExternalProductById,
  selectExternalProducts,
  type ExternalProductDto
} from "./external-products.repository";

const toDto = (body: Record<string, unknown>): ExternalProductDto => {
  const productUrl = asOptionalString(body.productUrl ?? body.product_url ?? body.sourceUrl ?? body.source_url);
  const mallName = asOptionalString(body.mallName ?? body.mall_name ?? body.sourceSite ?? body.source_site);
  const imageUrl = asOptionalString(body.imageUrl ?? body.image_url ?? body.thumbnailUrl ?? body.thumbnail_url);
  return {
    product_name: asRequiredString(body.productName ?? body.product_name, "productName"),
    brand: asOptionalString(body.brand),
    mall_name: mallName,
    product_url: productUrl,
    category: asRequiredString(body.category, "category") as ExternalProductDto["category"],
    fit_type: (asOptionalString(body.fitType ?? body.fit_type) ?? "regular") as ExternalProductDto["fit_type"],
    image_url: imageUrl,
    source_url: productUrl,
    source_site: mallName,
    source_product_id: asOptionalString(body.sourceProductId ?? body.source_product_id),
    thumbnail_url: imageUrl,
    raw_category: asOptionalString(body.rawCategory ?? body.raw_category),
    normalized_category: asOptionalString(body.normalizedCategory ?? body.normalized_category),
    imported_from_url: body.importedFromUrl === true || body.imported_from_url === true,
    import_metadata: asOptionalRecord(body.importMetadata ?? body.import_metadata),
    raw_product_data: asOptionalRecord(body.rawProductData ?? body.raw_product_data)
  };
};

export const createExternalProductForUser = (userId: string, body: Record<string, unknown>) =>
  insertExternalProduct(userId, toDto(body));

export const listExternalProductsForUser = (userId: string) => selectExternalProducts(userId);

export const getExternalProductForUser = (userId: string, id: string) => selectExternalProductById(userId, id);

export const updateExternalProductForUser = (userId: string, id: string, body: Record<string, unknown>) =>
  patchExternalProduct(userId, id, toDto(body));
