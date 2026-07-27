import { describe, expect, it } from "vitest";
import { extractDomProduct } from "../crawler/dom-parser";
import { toFitLabUrlPrefill } from "../fit-lab-prefill.mapper";

describe("Musinsa size chart import", () => {
  it("preserves transposed hydration table cells and maps circumference to flat width", () => {
    // Given
    const table = String.raw`
      \u003ctable\u003e
        \u003ctr\u003e\u003cth\u003e사이즈\u003c/th\u003e\u003ctd\u003eS\u003c/td\u003e\u003ctd\u003eM\u003c/td\u003e\u003ctd\u003eL\u003c/td\u003e\u003c/tr\u003e
        \u003ctr\u003e\u003cth\u003e옷길이\u003c/th\u003e\u003ctd\u003e57\u003c/td\u003e\u003ctd\u003e58.5\u003c/td\u003e\u003ctd\u003e60\u003c/td\u003e\u003c/tr\u003e
        \u003ctr\u003e\u003cth\u003e어깨너비\u003c/th\u003e\u003ctd\u003e39\u003c/td\u003e\u003ctd\u003e40.5\u003c/td\u003e\u003ctd\u003e42\u003c/td\u003e\u003c/tr\u003e
        \u003ctr\u003e\u003cth\u003e가슴둘레\u003c/th\u003e\u003ctd\u003e94\u003c/td\u003e\u003ctd\u003e99\u003c/td\u003e\u003ctd\u003e106\u003c/td\u003e\u003c/tr\u003e
        \u003ctr\u003e\u003cth\u003e소매길이\u003c/th\u003e\u003ctd\u003e21\u003c/td\u003e\u003ctd\u003e21.5\u003c/td\u003e\u003ctd\u003e22\u003c/td\u003e\u003c/tr\u003e
      \u003c/table\u003e`;
    const html = `<meta property="og:title" content="빈폴골프 반팔 티셔츠"><script>self.data="${table}"</script>`;

    // When
    const product = extractDomProduct({
      html,
      baseUrl: new URL("https://www.musinsa.com/products/5219138"),
      includeImages: false,
      includeDetailImages: false
    });
    const mapped = toFitLabUrlPrefill({
      partial: false,
      source: {
        site: "musinsa",
        url: "https://www.musinsa.com/products/5219138"
      },
      product: {
        name: product.name ?? "",
        brand: product.brand,
        normalizedCategory: "TOP"
      },
      sizeChart: { normalizedRows: product.sizeTable?.normalizedRows ?? [] }
    });

    // Then
    expect(product.sizeTable?.rawHeaders).toEqual(["사이즈", "S", "M", "L"]);
    expect(product.sizeTable?.rawRows).toEqual([
      ["옷길이", "57", "58.5", "60"],
      ["어깨너비", "39", "40.5", "42"],
      ["가슴둘레", "94", "99", "106"],
      ["소매길이", "21", "21.5", "22"]
    ]);
    expect(mapped.sizes).toEqual([
      {
        sizeLabel: "S",
        shoulderWidth: 39,
        chestWidth: 47,
        totalLength: 57,
        sleeveLength: 21,
        waistWidth: null,
        hipWidth: null,
        rise: null,
        outseam: null
      },
      {
        sizeLabel: "M",
        shoulderWidth: 40.5,
        chestWidth: 49.5,
        totalLength: 58.5,
        sleeveLength: 21.5,
        waistWidth: null,
        hipWidth: null,
        rise: null,
        outseam: null
      },
      {
        sizeLabel: "L",
        shoulderWidth: 42,
        chestWidth: 53,
        totalLength: 60,
        sleeveLength: 22,
        waistWidth: null,
        hipWidth: null,
        rise: null,
        outseam: null
      }
    ]);
  });
});
