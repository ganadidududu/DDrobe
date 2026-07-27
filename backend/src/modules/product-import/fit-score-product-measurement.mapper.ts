import type { MeasurementKey, MeasurementMap } from "../../shared/types/database";
import type { ProductImportPreview } from "./product-import.types";

const FIT_KEYS: Readonly<Record<string, MeasurementKey>> = {
  totalLength: "total_length",
  shoulderWidth: "shoulder_width",
  chestWidth: "chest_width",
  sleeveLength: "sleeve_length",
  waistWidth: "waist_width",
  hipWidth: "hip_width",
  frontRise: "rise",
  outseam: "outseam"
};

export type CoorditProductMeasurementInput = {
  readonly sizeLabel: string;
  readonly measurements: MeasurementMap;
};

export interface FitScoreProductMeasurementMapper {
  map(preview: ProductImportPreview): readonly CoorditProductMeasurementInput[];
}

export class DefaultFitScoreProductMeasurementMapper implements FitScoreProductMeasurementMapper {
  public map(preview: ProductImportPreview): readonly CoorditProductMeasurementInput[] {
    return preview.sizeChart.normalizedRows.map((row) => {
      const measurements: MeasurementMap = {};
      for (const [sourceKey, value] of Object.entries(row.measurements)) {
        const targetKey = FIT_KEYS[sourceKey];
        if (!targetKey) continue;
        if (
          value.normalizedUnit === "cm"
          && value.normalizedValue !== null
          && value.confidence >= 0.85
          && value.measurementType !== "range"
          && value.measurementType !== "unknown"
        ) {
          measurements[targetKey] = value.normalizedValue;
        }
      }
      return { sizeLabel: row.sizeLabel, measurements };
    }).filter((row) => Object.keys(row.measurements).length > 0);
  }
}
