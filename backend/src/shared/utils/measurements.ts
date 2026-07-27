import type { MeasurementKey, MeasurementMap } from "../types/database";
import { asOptionalNumber } from "./request";

type LegacyMeasurementSource = MeasurementMap & {
  readonly inseam?: number | null;
};

export const measurementKeys: MeasurementKey[] = [
  "total_length",
  "shoulder_width",
  "chest_width",
  "sleeve_length",
  "waist_width",
  "hip_width",
  "rise",
  "outseam"
];

export const pickMeasurements = (source: Record<string, unknown>): MeasurementMap =>
  measurementKeys.reduce<MeasurementMap>((measurements, key) => {
    const value = asOptionalNumber(source[key]);
    if (value !== null) measurements[key] = value;
    return measurements;
  }, {});

export const rowToMeasurements = (source: LegacyMeasurementSource): MeasurementMap =>
  measurementKeys.reduce<MeasurementMap>((measurements, key) => {
    const value = key === "outseam" ? source.outseam ?? source.inseam : source[key];
    if (typeof value === "number" && Number.isFinite(value)) measurements[key] = value;
    return measurements;
  }, {});

export const toLegacyMeasurementStorage = <
  T extends object & { readonly outseam?: number | null }
>(
  source: T
): Omit<T, "outseam"> & { readonly inseam?: number } => {
  const { outseam, ...remaining } = source;
  return typeof outseam === "number" && Number.isFinite(outseam)
    ? { ...remaining, inseam: outseam }
    : remaining;
};

export const isMissingOutseamColumnError = (
  error: { readonly message?: string; readonly details?: string } | null
): boolean => {
  if (!error) return false;
  const description = `${error.message ?? ""} ${error.details ?? ""}`.toLowerCase();
  return description.includes("outseam")
    && (description.includes("column") || description.includes("schema cache"));
};
