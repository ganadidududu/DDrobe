import { load } from "cheerio";

export type ExtractedProductData = {
  readonly name: string | null;
  readonly brand: string | null;
  readonly category: string | null;
  readonly description: string | null;
  readonly productId: string | null;
  readonly images: readonly string[];
  readonly sizes: readonly string[];
  readonly colors: readonly string[];
  readonly price: number | null;
  readonly currency: string | null;
};

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const stringValue = (value: unknown): string | null =>
  typeof value === "string" && value.trim() ? value.trim() : null;

const firstString = (...values: readonly unknown[]): string | null => {
  for (const value of values) {
    const parsed = stringValue(value);
    if (parsed) return parsed;
  }
  return null;
};

const strings = (value: unknown): readonly string[] => {
  if (typeof value === "string") return value.trim() ? [value.trim()] : [];
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    if (typeof item === "string") return item.trim() ? [item.trim()] : [];
    if (isRecord(item)) {
      const url = firstString(item.url, item.contentUrl);
      return url ? [url] : [];
    }
    return [];
  });
};

const brandName = (value: unknown): string | null => {
  if (typeof value === "string") return stringValue(value);
  return isRecord(value) ? firstString(value.name, value.brandName) : null;
};

const isProductRecord = (value: Record<string, unknown>): boolean => {
  const type = value["@type"];
  const productType = type === "Product" || (Array.isArray(type) && type.includes("Product"));
  if (productType) return true;
  const keys = Object.keys(value).map((key) => key.toLowerCase());
  return keys.includes("productname") || (keys.includes("name") && keys.some((key) => /sku|productid|goodsno/.test(key)));
};

const findProductRecord = (root: unknown): Record<string, unknown> | null => {
  const queue: unknown[] = [root];
  let visited = 0;
  while (queue.length > 0 && visited < 10_000) {
    visited += 1;
    const value = queue.shift();
    if (isRecord(value)) {
      if (isProductRecord(value)) return value;
      queue.push(...Object.values(value));
    } else if (Array.isArray(value)) {
      queue.push(...value);
    }
  }
  return null;
};

const extractOptions = (record: Record<string, unknown>, keyword: RegExp): readonly string[] => {
  const result = new Set<string>();
  for (const [key, value] of Object.entries(record)) {
    if (!keyword.test(key)) continue;
    for (const item of strings(value)) result.add(item);
    if (isRecord(value)) {
      for (const nested of Object.values(value)) {
        for (const item of strings(nested)) result.add(item);
      }
    }
  }
  return [...result];
};

export const extractProductFromUnknown = (root: unknown): ExtractedProductData | null => {
  const record = findProductRecord(root);
  if (!record) return null;
  const offers = isRecord(record.offers)
    ? record.offers
    : Array.isArray(record.offers) && isRecord(record.offers[0]) ? record.offers[0] : {};
  const priceValue = firstString(record.price, record.salePrice, offers.price);
  const price = priceValue === null ? null : Number(priceValue.replace(/[^\d.]/g, ""));
  return {
    name: firstString(record.name, record.productName, record.goodsName, record.itemName),
    brand: brandName(record.brand) ?? firstString(record.brandName, record.maker),
    category: firstString(record.category, record.categoryName),
    description: firstString(record.description, record.productDescription),
    productId: firstString(record.productID, record.productId, record.goodsNo, record.sku),
    images: strings(record.image).concat(strings(record.images), strings(record.imageUrl)),
    sizes: extractOptions(record, /size|사이즈/i),
    colors: extractOptions(record, /color|colour|색상/i),
    price: price !== null && Number.isFinite(price) ? price : null,
    currency: firstString(record.priceCurrency, offers.priceCurrency)
  };
};

const parseJson = (text: string): unknown | null => {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
};

export const extractStructuredProduct = (html: string): ExtractedProductData | null => {
  const $ = load(html);
  const candidates: unknown[] = [];
  $('script[type="application/ld+json"], script#__NEXT_DATA__, script[type="application/json"]').each((_index, element) => {
    const parsed = parseJson($(element).text());
    if (parsed !== null) candidates.push(parsed);
  });
  for (const candidate of candidates) {
    const product = extractProductFromUnknown(candidate);
    if (product?.name) return product;
  }
  return null;
};
