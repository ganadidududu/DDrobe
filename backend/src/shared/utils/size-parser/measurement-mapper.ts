import type { MeasurementKey, MeasurementMap } from "../../types/database";
import { normalizeMeasurementValue } from "./normalize-size";

const aliases: Record<string, MeasurementKey> = {
  총장: "total_length",
  어깨: "shoulder_width",
  어깨너비: "shoulder_width",
  가슴: "chest_width",
  가슴단면: "chest_width",
  "가슴 너비": "chest_width",
  가슴너비: "chest_width",
  소매: "sleeve_length",
  소매길이: "sleeve_length",
  허리: "waist_width",
  엉덩이: "hip_width",
  밑위: "rise",
  아웃심: "outseam"
};

export const mapRawMeasurements = (raw: Record<string, unknown>): MeasurementMap =>
  Object.entries(raw).reduce<MeasurementMap>((mapped, [key, value]) => {
    const measurementKey = aliases[key.trim()] ?? (key as MeasurementKey);
    const normalized = normalizeMeasurementValue(value as string | number | null | undefined);
    if (normalized !== null) mapped[measurementKey] = normalized;
    return mapped;
  }, {});
