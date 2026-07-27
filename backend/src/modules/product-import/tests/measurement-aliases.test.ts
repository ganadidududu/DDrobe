import { describe, expect, it } from "vitest";
import { normalizeSizeTable } from "../normalization/product-normalizer";

describe("measurement aliases", () => {
  it("treats 가슴 너비 as a flat chest measurement", () => {
    const rows = normalizeSizeTable(
      ["사이즈", "가슴 너비", "총장"],
      [["M", "56", "70"]],
      "cm"
    );

    expect(rows[0]).toMatchObject({
      measurements: {
        chestWidth: { normalizedValue: 56, measurementType: "width" }
      },
      unknownMeasurements: {}
    });
  });
});
