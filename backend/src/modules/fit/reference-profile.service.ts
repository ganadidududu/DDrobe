import { supabase } from "../../config/supabase";
import { createHttpError } from "../../shared/utils/http-error";
import { rowToMeasurements } from "../../shared/utils/measurements";
import { BOTTOM_CATEGORIES, TOP_CATEGORIES } from "./fit.constants";
import {
  calculateFitScoreForReferenceProfile,
  calculateDynamicWeightsByReferenceVariance,
  calculateReferenceFitProfile,
  getWeightsByCategory
} from "./fit-score.engine";
import type {
  Category,
  ExternalProductSizeInput,
  FitType,
  MeasurementMap,
  MeasurementWeights,
  ReferenceFitProfile,
  ReferenceClothingInput
} from "./fit.types";

export const CLOSET_GARMENT_KINDS = ["upper", "lower"] as const;
export type ClosetGarmentKind = (typeof CLOSET_GARMENT_KINDS)[number];

interface DbReferenceClothing {
  readonly id: string;
  readonly clothing_item_id: string;
  readonly fit_type: FitType;
  readonly preference_score: number | null;
}

interface DbClothingSize extends MeasurementMap {
  readonly clothing_item_id: string;
  readonly size_label: string | null;
}

interface DbClosetClothingItem {
  readonly id: string;
  readonly category: Category;
  readonly fit_type: FitType;
  readonly size_label: string | null;
}

export interface ClosetReferenceProfile {
  readonly garmentKind: ClosetGarmentKind;
  readonly referenceCount: number;
  readonly measurements: MeasurementMap;
  readonly sampleCounts: Partial<Record<keyof MeasurementMap, number>>;
  readonly strategy: "weighted_huber_profile_v1" | "unavailable";
}

export type ClosetItemFitComparison =
  | {
      readonly status: "available";
      readonly garmentKind: ClosetGarmentKind;
      readonly referenceCount: number;
      readonly fitScore: number;
      readonly bestFitGap: number;
      readonly diff: MeasurementMap;
    }
  | {
      readonly status: "unavailable";
      readonly garmentKind: ClosetGarmentKind;
      readonly referenceCount: number;
      readonly reason: "missing_reference" | "missing_measurements";
    };

type ClosetProfileConfig = {
  readonly categories: readonly Category[];
  readonly profileCategory: Category;
};

type ClosetReferenceProfileContext =
  | {
      readonly status: "unavailable";
      readonly garmentKind: ClosetGarmentKind;
      readonly referenceCount: number;
    }
  | {
      readonly status: "available";
      readonly garmentKind: ClosetGarmentKind;
      readonly referenceCount: number;
      readonly profile: ReferenceFitProfile;
      readonly weights: MeasurementWeights;
    };

const profileConfig: Record<
  ClosetGarmentKind,
  ClosetProfileConfig
> = {
  upper: { categories: TOP_CATEGORIES, profileCategory: "shirt" },
  lower: { categories: BOTTOM_CATEGORIES, profileCategory: "pants" }
};

const referenceProfileContext = async (
  userId: string,
  garmentKind: ClosetGarmentKind
): Promise<ClosetReferenceProfileContext> => {
  const config = profileConfig[garmentKind];
  const { data: references, error: referenceError } = await supabase
    .from("reference_clothing")
    .select("id, clothing_item_id, fit_type, preference_score")
    .eq("user_id", userId)
    .eq("is_active", true)
    .in("category", [...config.categories])
    .returns<DbReferenceClothing[]>();

  if (referenceError) {
    throw createHttpError(500, "Failed to load active reference clothing");
  }
  if (!references || references.length === 0) {
    return { status: "unavailable", garmentKind, referenceCount: 0 };
  }

  const clothingItemIds = references.map((reference) => reference.clothing_item_id);
  const { data: sizes, error: sizeError } = await supabase
    .from("clothing_sizes")
    .select("*")
    .eq("user_id", userId)
    .in("clothing_item_id", clothingItemIds)
    .returns<DbClothingSize[]>();

  if (sizeError) {
    throw createHttpError(500, "Failed to load reference clothing measurements");
  }

  const sizeByItemId = new Map(
    (sizes ?? []).map((size) => [size.clothing_item_id, size])
  );
  const inputs = references.flatMap<ReferenceClothingInput>((reference) => {
    const size = sizeByItemId.get(reference.clothing_item_id);
    if (!size) return [];
    return [{
      id: reference.id,
      clothingItemId: reference.clothing_item_id,
      sizeLabel: size.size_label,
      fitType: reference.fit_type,
      preferenceScore: reference.preference_score ?? 100,
      measurements: rowToMeasurements(size)
    }];
  });

  if (inputs.length === 0) {
    return { status: "unavailable", garmentKind, referenceCount: 0 };
  }

  const baseWeights = getWeightsByCategory(config.profileCategory);
  const { dynamicWeights } = calculateDynamicWeightsByReferenceVariance(baseWeights, inputs);
  return {
    status: "available",
    garmentKind,
    referenceCount: inputs.length,
    profile: calculateReferenceFitProfile(inputs, dynamicWeights),
    weights: dynamicWeights
  };
};

const garmentKindForCategory = (category: Category): ClosetGarmentKind =>
  profileConfig.upper.categories.includes(category) ? "upper" : "lower";

export const getClosetReferenceProfile = async (
  userId: string,
  garmentKind: ClosetGarmentKind
): Promise<ClosetReferenceProfile> => {
  const context = await referenceProfileContext(userId, garmentKind);
  switch (context.status) {
    case "unavailable":
      return {
        garmentKind,
        referenceCount: context.referenceCount,
        measurements: {},
        sampleCounts: {},
        strategy: "unavailable"
      };
    case "available":
      return {
        garmentKind,
        referenceCount: context.referenceCount,
        measurements: context.profile.measurements,
        sampleCounts: context.profile.sampleCounts,
        strategy: context.profile.strategy
      };
  }
};

export const getClosetItemFitComparison = async (
  userId: string,
  clothingItemId: string
): Promise<ClosetItemFitComparison> => {
  const { data: clothingItem, error: itemError } = await supabase
    .from("clothing_items")
    .select("id, category, fit_type, size_label")
    .eq("user_id", userId)
    .eq("id", clothingItemId)
    .single<DbClosetClothingItem>();

  if (itemError || !clothingItem) {
    throw createHttpError(404, "Closet clothing item was not found");
  }

  const garmentKind = garmentKindForCategory(clothingItem.category);
  const context = await referenceProfileContext(userId, garmentKind);
  switch (context.status) {
    case "unavailable":
      return {
        status: "unavailable",
        garmentKind,
        referenceCount: context.referenceCount,
        reason: "missing_reference"
      };
    case "available":
      break;
  }

  const { data: sizes, error: sizeError } = await supabase
    .from("clothing_sizes")
    .select("*")
    .eq("user_id", userId)
    .eq("clothing_item_id", clothingItem.id)
    .returns<DbClothingSize[]>();
  const size = sizes?.[0];
  if (sizeError || !size) {
    return {
      status: "unavailable",
      garmentKind,
      referenceCount: context.referenceCount,
      reason: "missing_measurements"
    };
  }

  const candidate: ExternalProductSizeInput = {
    id: clothingItem.id,
    sizeLabel: clothingItem.size_label ?? size.size_label ?? "등록 사이즈",
    fitType: clothingItem.fit_type,
    measurements: rowToMeasurements(size)
  };
  const score = calculateFitScoreForReferenceProfile(
    context.profile,
    candidate,
    clothingItem.category,
    context.weights
  );
  return {
    status: "available",
    garmentKind,
    referenceCount: context.referenceCount,
    fitScore: score.finalFitScore,
    bestFitGap: Math.max(0, 100 - score.finalFitScore),
    diff: score.diffs
  };
};
