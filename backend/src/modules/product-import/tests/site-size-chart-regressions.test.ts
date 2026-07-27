import { describe, expect, it } from "vitest";
import { extractSizeChartFromUnknown } from "../crawler/size-chart-parser";
import { toFitLabUrlPrefill } from "../fit-lab-prefill.mapper";
import {
  normalizeCategory,
  normalizeSizeTable
} from "../normalization/product-normalizer";

describe("site size-chart regressions", () => {
  it("extracts Musinsa actual-size API rows", () => {
    const response = {
      data: {
        typeName: "긴소매티셔츠",
        sizes: [
          {
            name: "XS",
            items: [
              { name: "총장", value: 61, recommendSizeRange: 5 },
              { name: "어깨너비", value: 32.7, recommendSizeRange: 5 },
              { name: "가슴단면", value: 39, recommendSizeRange: 5 },
              { name: "소매길이", value: 58.3, recommendSizeRange: 5 }
            ]
          },
          {
            name: "S",
            items: [
              { name: "총장", value: 62, recommendSizeRange: 5 },
              { name: "어깨너비", value: 34, recommendSizeRange: 5 },
              { name: "가슴단면", value: 41.5, recommendSizeRange: 5 },
              { name: "소매길이", value: 59, recommendSizeRange: 5 }
            ]
          }
        ]
      }
    };

    const chart = extractSizeChartFromUnknown(response);

    expect(chart).toMatchObject({
      unit: "cm",
      rawHeaders: ["사이즈", "총장", "어깨너비", "가슴단면", "소매길이"],
      rawRows: [
        ["XS", "61", "32.7", "39", "58.3"],
        ["S", "62", "34", "41.5", "59"]
      ]
    });
    expect(chart?.normalizedRows[0]).toMatchObject({
      sizeLabel: "XS",
      measurements: {
        totalLength: { normalizedValue: 61 },
        shoulderWidth: { normalizedValue: 32.7 },
        chestWidth: { normalizedValue: 39 },
        sleeveLength: { normalizedValue: 58.3 }
      }
    });
  });

  it("infers garment category from the product text when metadata is missing", () => {
    expect(normalizeCategory(
      "무신사 스탠다드 우먼 우먼즈 텐셀 슬림 터틀 넥 티셔츠 제품분류 상의 긴소매 티셔츠"
    )).toBe("TOP");
    expect(normalizeCategory(
      "무신사 스탠다드 우먼 우먼즈 와이드 데님 팬츠 제품분류 하의 청바지"
    )).toBe("JEANS");
  });

  it("extracts Ably structured measurement sizes when no text table exists", () => {
    // Given
    const response = {
      pieces: [{
        measurement: {
          sizes: [{
            name: "FREE",
            measure_values: [
              { value: 77, spot: { name: "총장" } },
              { value: 61, spot: { name: "어깨단면" } },
              { value: 56, spot: { name: "소매길이" } },
              { value: 69.5, spot: { name: "가슴단면" } }
            ]
          }]
        }
      }]
    };

    // When
    const chart = extractSizeChartFromUnknown(response);

    // Then
    expect(chart).toMatchObject({
      rawHeaders: ["사이즈", "총장", "어깨단면", "소매길이", "가슴단면"],
      rawRows: [["FREE", "77", "61", "56", "69.5"]]
    });
    expect(chart?.normalizedRows[0]).toMatchObject({
      sizeLabel: "FREE",
      measurements: {
        totalLength: { normalizedValue: 77 },
        shoulderWidth: { normalizedValue: 61 },
        sleeveLength: { normalizedValue: 56 },
        chestWidth: { normalizedValue: 69.5 }
      }
    });
  });

  it("maps 29CM bare chest headers to chest width", () => {
    // Given
    const headers = ["사이즈", "어깨", "가슴", "소매", "총장"];
    const rows = [["1(M)", "48", "58", "61", "67"]];

    // When
    const normalized = normalizeSizeTable(headers, rows, "cm");

    // Then
    expect(normalized[0]).toMatchObject({
      sizeLabel: "1(M)",
      measurements: {
        shoulderWidth: { normalizedValue: 48 },
        chestWidth: { normalizedValue: 58 },
        sleeveLength: { normalizedValue: 61 },
        totalLength: { normalizedValue: 67 }
      },
      unknownMeasurements: {}
    });
  });

  it("normalizes Musinsa transposed tables with a blank corner header", () => {
    // Given
    const headers = ["", "95", "100", "105", "110"];
    const rows = [
      ["어깨너비", "47", "49", "51", "53"],
      ["소매길이", "24", "25", "26", "27"],
      ["총길이", "68", "70", "72", "74"],
      ["가슴둘레", "110", "115", "120", "125"]
    ];

    // When
    const normalized = normalizeSizeTable(headers, rows, "cm");

    // Then
    expect(normalized).toHaveLength(4);
    expect(normalized[0]).toMatchObject({
      sizeLabel: "95",
      measurements: {
        shoulderWidth: { normalizedValue: 47 },
        sleeveLength: { normalizedValue: 24 },
        totalLength: { normalizedValue: 68 },
        chestCircumference: { normalizedValue: 110 }
      }
    });
  });

  it("normalizes 29CM lower-garment width header variants", () => {
    // Given
    const headers = [
      "사이즈명 (cm)", "총길이", "허리 너비", "엉덩이 너비",
      "밑위 너비", "허벅지 너비", "밑단 너비"
    ];
    const rows = [["W28 / L32", "109", "38", "53", "33", "34", "27"]];

    // When
    const normalized = normalizeSizeTable(headers, rows, "cm");

    // Then
    expect(normalized[0]).toMatchObject({
      measurements: {
        totalLength: { normalizedValue: 109 },
        waistWidth: { normalizedValue: 38 },
        hipWidth: { normalizedValue: 53 },
        frontRise: { normalizedValue: 33 },
        thighWidth: { normalizedValue: 34 },
        legOpening: { normalizedValue: 27 }
      },
      unknownMeasurements: {}
    });
  });

  it("uses total length as outseam for 29CM pants prefill", () => {
    // Given
    const normalizedRows = normalizeSizeTable(
      ["사이즈", "총장", "허리", "엉덩이", "밑위"],
      [["S", "105", "39", "51", "33.5"]],
      "cm"
    );

    // When
    const prefill = toFitLabUrlPrefill({
      partial: false,
      source: { site: "29cm", url: "https://product.29cm.co.kr/catalog/3114180" },
      product: {
        name: "와이드 치노 팬츠 브라운",
        brand: null,
        normalizedCategory: "PANTS"
      },
      sizeChart: { normalizedRows }
    });

    // Then
    expect(prefill.sizes[0]).toMatchObject({
      sizeLabel: "S",
      waistWidth: 39,
      hipWidth: 51,
      rise: 33.5,
      outseam: 105
    });
  });
});
