import type {
  NormalizedCategory,
  NormalizedMeasurementValue,
  NormalizedSizeRow,
  ProductSite
} from "./product-import.types";

type FitLabPrefillInput = {
  readonly partial: boolean;
  readonly source: {
    readonly site: ProductSite;
    readonly url: string;
  };
  readonly product: {
    readonly name: string;
    readonly brand: string | null;
    readonly normalizedCategory: NormalizedCategory;
  };
  readonly sizeChart: {
    readonly normalizedRows: readonly NormalizedSizeRow[];
  };
};

export const FIT_LAB_CATEGORIES = [
  "tshirt",
  "shirt",
  "sweatshirt",
  "hoodie",
  "knit",
  "jacket",
  "coat",
  "pants",
  "jeans",
  "shorts",
  "skirt"
] as const;

export type FitLabCategory = typeof FIT_LAB_CATEGORIES[number];

const CATEGORY_MAP: Readonly<Record<NormalizedCategory, FitLabCategory>> = {
  TOP: "tshirt",
  SHIRT: "shirt",
  KNIT: "knit",
  SWEATSHIRT: "sweatshirt",
  HOODIE: "hoodie",
  OUTER: "jacket",
  JACKET: "jacket",
  COAT: "coat",
  PANTS: "pants",
  JEANS: "jeans",
  SHORTS: "shorts",
  SKIRT: "skirt",
  DRESS: "skirt",
  SHOES: "tshirt",
  HAT: "tshirt",
  BAG: "tshirt",
  ACCESSORY: "tshirt",
  UNKNOWN: "tshirt"
};

const LOWER_GARMENT_CATEGORIES: ReadonlySet<FitLabCategory> = new Set([
  "pants", "jeans", "shorts", "skirt"
]);

const numericValue = (value: NormalizedMeasurementValue | undefined): number | null =>
  value?.normalizedValue ?? null;

const flatWidthValue = (
  width: NormalizedMeasurementValue | undefined,
  circumference: NormalizedMeasurementValue | undefined
): number | null => {
  const widthValue = numericValue(width);
  if (widthValue !== null) return widthValue;
  const circumferenceValue = numericValue(circumference);
  return circumferenceValue === null ? null : circumferenceValue / 2;
};

export const toFitLabUrlPrefill = (
  preview: FitLabPrefillInput,
  categoryOverride?: FitLabCategory
) => {
  const category = categoryOverride ?? CATEGORY_MAP[preview.product.normalizedCategory];
  return {
    productName: preview.product.name,
    brand: preview.product.brand,
    mallName: preview.source.site,
    productUrl: preview.source.url,
    category,
    fitType: "regular",
    parsingStatus: preview.partial ? "partial" : "parsed",
    sizes: preview.sizeChart.normalizedRows.map((row) => ({
      sizeLabel: row.sizeLabel,
      shoulderWidth: numericValue(row.measurements.shoulderWidth),
      chestWidth: flatWidthValue(row.measurements.chestWidth, row.measurements.chestCircumference),
      totalLength: numericValue(row.measurements.totalLength),
      sleeveLength: numericValue(row.measurements.sleeveLength),
      waistWidth: flatWidthValue(row.measurements.waistWidth, row.measurements.waistCircumference),
      hipWidth: flatWidthValue(row.measurements.hipWidth, row.measurements.hipCircumference),
      rise: numericValue(row.measurements.frontRise),
      outseam: numericValue(row.measurements.outseam)
        ?? (LOWER_GARMENT_CATEGORIES.has(category)
          ? numericValue(row.measurements.totalLength)
          : null)
    }))
  };
};
