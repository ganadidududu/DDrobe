import { z } from "zod";
import { NORMALIZED_CATEGORIES, PRODUCT_SITES } from "./product-import.types";

export const productImportRequestSchema = z.object({
  url: z.string().trim().min(1).max(2048),
  includeImages: z.boolean().default(true),
  includeDetailImages: z.boolean().default(false)
}).strict();

const measurementValueSchema = z.object({
  rawValue: z.string().nullable(),
  rawUnit: z.enum(["cm", "mm", "inch", "unknown"]),
  normalizedValue: z.number().nullable(),
  normalizedUnit: z.enum(["cm", "mm", "inch", "unknown"]),
  converted: z.boolean(),
  measurementType: z.enum(["width", "circumference", "length", "range", "unknown"]),
  confidence: z.number().min(0).max(1),
  warning: z.string().optional()
});

export const productImportPreviewSchema = z.object({
  success: z.literal(true),
  partial: z.boolean(),
  source: z.object({
    site: z.enum(PRODUCT_SITES),
    url: z.url(),
    productId: z.string().nullable(),
    crawledAt: z.iso.datetime()
  }),
  product: z.object({
    name: z.string().min(1),
    brand: z.string().nullable(),
    rawCategory: z.string().nullable(),
    normalizedCategory: z.enum(NORMALIZED_CATEGORIES),
    price: z.object({
      original: z.number().nullable(),
      sale: z.number().nullable(),
      currency: z.string().nullable()
    }).nullable(),
    gender: z.string().nullable(),
    materials: z.array(z.string()),
    description: z.string().nullable(),
    soldOut: z.boolean().nullable()
  }),
  images: z.object({
    thumbnail: z.url().nullable(),
    main: z.array(z.url()),
    detail: z.array(z.url()),
    sizeChartImage: z.url().nullable()
  }),
  options: z.object({
    colors: z.array(z.string()),
    sizes: z.array(z.string())
  }),
  sizeChart: z.object({
    found: z.boolean(),
    type: z.enum(["productMeasurement", "recommendedBodyMeasurement"]).nullable(),
    unit: z.enum(["cm", "mm", "inch", "unknown"]),
    rawHeaders: z.array(z.string()),
    rawRows: z.array(z.array(z.string())),
    normalizedRows: z.array(z.object({
      sizeLabel: z.string(),
      measurements: z.record(z.string(), measurementValueSchema),
      unknownMeasurements: z.record(z.string(), measurementValueSchema)
    })),
    notes: z.array(z.string()),
    requiresOcr: z.boolean(),
    ocrAvailable: z.boolean()
  }),
  metadata: z.object({
    adapter: z.enum(PRODUCT_SITES),
    extractionMethods: z.array(z.enum(["structured-data", "network-json", "dom"])),
    confidence: z.number().min(0).max(1),
    warnings: z.array(z.string()),
    fieldSources: z.record(z.string(), z.object({
      method: z.enum(["structured-data", "network-json", "dom"]),
      confidence: z.number().min(0).max(1)
    }))
  })
});

export type ProductImportRequest = z.infer<typeof productImportRequestSchema>;
