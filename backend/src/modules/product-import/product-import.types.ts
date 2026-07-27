export const PRODUCT_SITES = [
  "musinsa",
  "29cm",
  "ably",
  "wconcept",
  "naver-smart-store",
  "zigzag",
  "generic"
] as const;

export type ProductSite = (typeof PRODUCT_SITES)[number];

export const NORMALIZED_CATEGORIES = [
  "TOP", "SHIRT", "KNIT", "SWEATSHIRT", "HOODIE", "OUTER", "JACKET", "COAT",
  "PANTS", "JEANS", "SHORTS", "SKIRT", "DRESS", "SHOES", "HAT", "BAG",
  "ACCESSORY", "UNKNOWN"
] as const;

export type NormalizedCategory = (typeof NORMALIZED_CATEGORIES)[number];
export type MeasurementUnit = "cm" | "mm" | "inch" | "unknown";
export type MeasurementType = "width" | "circumference" | "length" | "range" | "unknown";
export type ExtractionMethod = "structured-data" | "network-json" | "dom";

export type NormalizedMeasurementValue = {
  readonly rawValue: string | null;
  readonly rawUnit: MeasurementUnit;
  readonly normalizedValue: number | null;
  readonly normalizedUnit: MeasurementUnit;
  readonly converted: boolean;
  readonly measurementType: MeasurementType;
  readonly confidence: number;
  readonly warning?: string;
};

export type NormalizedSizeRow = {
  readonly sizeLabel: string;
  readonly measurements: Readonly<Record<string, NormalizedMeasurementValue>>;
  readonly unknownMeasurements: Readonly<Record<string, NormalizedMeasurementValue>>;
};

export type ProductImportPreview = {
  readonly success: true;
  readonly partial: boolean;
  readonly source: {
    readonly site: ProductSite;
    readonly url: string;
    readonly productId: string | null;
    readonly crawledAt: string;
  };
  readonly product: {
    readonly name: string;
    readonly brand: string | null;
    readonly rawCategory: string | null;
    readonly normalizedCategory: NormalizedCategory;
    readonly price: {
      readonly original: number | null;
      readonly sale: number | null;
      readonly currency: string | null;
    } | null;
    readonly gender: string | null;
    readonly materials: readonly string[];
    readonly description: string | null;
    readonly soldOut: boolean | null;
  };
  readonly images: {
    readonly thumbnail: string | null;
    readonly main: readonly string[];
    readonly detail: readonly string[];
    readonly sizeChartImage: string | null;
  };
  readonly options: {
    readonly colors: readonly string[];
    readonly sizes: readonly string[];
  };
  readonly sizeChart: {
    readonly found: boolean;
    readonly type: "productMeasurement" | "recommendedBodyMeasurement" | null;
    readonly unit: MeasurementUnit;
    readonly rawHeaders: readonly string[];
    readonly rawRows: readonly (readonly string[])[];
    readonly normalizedRows: readonly NormalizedSizeRow[];
    readonly notes: readonly string[];
    readonly requiresOcr: boolean;
    readonly ocrAvailable: boolean;
  };
  readonly metadata: {
    readonly adapter: ProductSite;
    readonly extractionMethods: readonly ExtractionMethod[];
    readonly confidence: number;
    readonly warnings: readonly string[];
    readonly fieldSources: Readonly<Record<string, {
      readonly method: ExtractionMethod;
      readonly confidence: number;
    }>>;
  };
};

export type ProductImportErrorCode =
  | "INVALID_URL" | "UNSUPPORTED_PROTOCOL" | "BLOCKED_PRIVATE_NETWORK"
  | "UNSUPPORTED_SITE" | "PRODUCT_PAGE_NOT_ACCESSIBLE" | "PRODUCT_NOT_FOUND"
  | "PRODUCT_NAME_NOT_FOUND" | "SIZE_CHART_NOT_FOUND" | "SIZE_CHART_PARSE_FAILED"
  | "CRAWL_TIMEOUT" | "RESPONSE_TOO_LARGE" | "RATE_LIMITED"
  | "SITE_BLOCKED_REQUEST" | "INTERNAL_CRAWLER_ERROR";

export type ProductImportFailure = {
  readonly success: false;
  readonly error: {
    readonly code: ProductImportErrorCode;
    readonly message: string;
    readonly retryable: boolean;
  };
  readonly partialData: ProductImportPreview | null;
};

export type ProductImportResult = ProductImportPreview | ProductImportFailure;

export type OcrSizeChartResult = {
  readonly rawHeaders: readonly string[];
  readonly rawRows: readonly (readonly string[])[];
  readonly confidence: number;
};

export interface SizeChartOcrService {
  extract(imageUrl: string): Promise<OcrSizeChartResult>;
}

export type ProductCrawlContext = {
  readonly url: URL;
  readonly includeImages: boolean;
  readonly includeDetailImages: boolean;
  readonly crawledAt: string;
};

export interface ProductCrawlerAdapter {
  readonly name: ProductSite;
  supports(url: URL): boolean;
  extract(context: ProductCrawlContext): Promise<ProductImportPreview>;
}
