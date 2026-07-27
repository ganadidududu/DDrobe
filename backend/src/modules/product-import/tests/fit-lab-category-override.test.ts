import { describe, expect, it } from "vitest";
import { toFitLabUrlPrefill } from "../fit-lab-prefill.mapper";
import { normalizeSizeTable } from "../normalization/product-normalizer";

describe("Fit Lab category override", () => {
  it("uses the user's category choice instead of an incorrect crawler category", () => {
    const normalizedRows = normalizeSizeTable(
      ["사이즈", "총장", "허리단면"],
      [["S", "86.5", "33.25"]],
      "cm"
    );

    const mapped = toFitLabUrlPrefill({
      partial: false,
      source: {
        site: "musinsa",
        url: "https://www.musinsa.com/products/4457755"
      },
      product: {
        name: "우먼즈 스트레이트 맥시 스커트",
        brand: "무신사 스탠다드 우먼",
        normalizedCategory: "TOP"
      },
      sizeChart: { normalizedRows }
    }, "skirt");

    expect(mapped.category).toBe("skirt");
    expect(mapped.sizes[0]).toMatchObject({
      sizeLabel: "S",
      waistWidth: 33.25,
      outseam: 86.5
    });
  });
});
