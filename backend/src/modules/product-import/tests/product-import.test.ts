import { describe, expect, it } from "vitest";
import {
  AblyAdapter,
  MusinsaAdapter,
  NaverSmartStoreAdapter,
  toWConceptMobileUrl
} from "../adapters/product-crawler-adapters";
import { extractDomProduct, parseBestSizeTable } from "../crawler/dom-parser";
import {
  extractSizeChartFromUnknown,
  extractSizeChartImageFromUnknown,
  parseMeasurementText
} from "../crawler/size-chart-parser";
import { extractStructuredProduct } from "../crawler/structured-data-parser";
import {
  normalizeMeasurement,
  normalizeSizeTable
} from "../normalization/product-normalizer";
import { toFitLabUrlPrefill } from "../fit-lab-prefill.mapper";
import { ProductImportError } from "../product-import.error";
import {
  assertPublicUrl,
  isPrivateIpAddress,
  parseProductUrl
} from "../security/url-validator";
import { effectiveCrawlerSite, productIdFromUrl } from "../crawler/product-page-crawler";

describe("product-import URL security and adapter routing", () => {
  it("uses Musinsa size-chart handling after a share link resolves to a Musinsa product", () => {
    expect(effectiveCrawlerSite(
      "generic",
      new URL("https://www.musinsa.com/products/6252903")
    )).toBe("musinsa");
  });

  it("uses the Musinsa product path instead of a tracking query number for the size API", () => {
    expect(productIdFromUrl(
      new URL("https://www.musinsa.com/products/6064539?af_siteid=1003139529")
    )).toBe("6064539");
  });

  it("matches supported public shop domains without matching lookalikes", () => {
    expect(new MusinsaAdapter().supports(new URL("https://www.musinsa.com/products/1234567"))).toBe(true);
    expect(new MusinsaAdapter().supports(new URL("https://musinsa.com.attacker.example/products/1"))).toBe(false);
    expect(new AblyAdapter().supports(new URL("https://m.a-bly.com/goods/1234"))).toBe(true);
    expect(new NaverSmartStoreAdapter().supports(new URL("https://smartstore.naver.com/shop/products/1234"))).toBe(true);
  });

  it("uses W Concept's accessible mobile product page for legacy product URLs", () => {
    expect(toWConceptMobileUrl(new URL("https://www.wconcept.co.kr/Product/307237838")).href)
      .toBe("https://m.wconcept.co.kr/Product/307237838");
  });

  it("rejects malformed and unsupported URLs", () => {
    expect(() => parseProductUrl("not a url")).toThrow(ProductImportError);
    expect(() => parseProductUrl("file:///etc/passwd")).toThrow(ProductImportError);
  });

  it("blocks loopback and private network targets including redirect destinations", async () => {
    expect(isPrivateIpAddress("127.0.0.1")).toBe(true);
    expect(isPrivateIpAddress("10.0.0.8")).toBe(true);
    expect(isPrivateIpAddress("172.16.1.2")).toBe(true);
    expect(isPrivateIpAddress("192.168.1.2")).toBe(true);
    await expect(assertPublicUrl(new URL("http://localhost/admin"))).rejects.toMatchObject({
      code: "BLOCKED_PRIVATE_NETWORK"
    });
    await expect(assertPublicUrl(new URL("http://127.0.0.1/redirected"))).rejects.toMatchObject({
      code: "BLOCKED_PRIVATE_NETWORK"
    });
  });
});

describe("structured product parsing", () => {
  it("extracts JSON-LD product data", () => {
    const html = `<script type="application/ld+json">${JSON.stringify({
      "@type": "Product",
      name: "코튼 티셔츠",
      brand: { name: "COORDIT" },
      image: ["https://cdn.example.com/main.jpg"],
      offers: { price: "29000", priceCurrency: "KRW" }
    })}</script>`;
    expect(extractStructuredProduct(html)).toMatchObject({
      name: "코튼 티셔츠",
      brand: "COORDIT",
      price: 29000,
      currency: "KRW"
    });
  });

  it("extracts nested Next.js hydration product data", () => {
    const html = `<script id="__NEXT_DATA__" type="application/json">${JSON.stringify({
      props: { pageProps: { product: { productId: "55", productName: "니트", brandName: "브랜드" } } }
    })}</script>`;
    expect(extractStructuredProduct(html)).toMatchObject({
      name: "니트",
      brand: "브랜드",
      productId: "55"
    });
  });
});

describe("size chart parsing and normalization", () => {
  it("parses 29CM and Zigzag measurement sentences without table markup", () => {
    const parsed = parseMeasurementText(`
      사이즈 (단위 cm)
      M 총장 116 가슴 96 허리 104 소매 26
      L 총장 117 가슴 100 허리 108 소매 27
    `);
    expect(parsed).toMatchObject({
      unit: "cm",
      rawHeaders: ["사이즈", "총장", "가슴", "허리", "소매"],
      rawRows: [
        ["M", "116", "96", "104", "26"],
        ["L", "117", "100", "108", "27"]
      ]
    });
  });

  it("parses measurement HTML nested in a public network JSON response", () => {
    const parsed = extractSizeChartFromUnknown({
      detail_html: `
        <div>총장 80</div><div>어깨 32.5</div>
        <div>가슴 38</div><div>허리 29</div>
        <div>모델 가슴둘레 32 inch</div>
      `
    });
    expect(parsed).toMatchObject({
      unit: "unknown",
      rawHeaders: ["사이즈", "총장", "어깨", "가슴", "허리"],
      rawRows: [["FREE", "80", "32.5", "38", "29"]]
    });
  });

  it("finds a size-chart image in a measurement JSON field", () => {
    expect(extractSizeChartImageFromUnknown({
      goods_extracted_measure_image: {
        image_url: "https://cdn.example.com/extracted-size.png"
      }
    })).toBe("https://cdn.example.com/extracted-size.png");
  });

  it("parses HTML escaped inside a hydration script", () => {
    const parsed = parseMeasurementText(
      String.raw`<script>self.data="\u003cp\u003eM 총장 116 가슴 96 허리 104 소매 26\u003c/p\u003e\n\u003cp\u003eL 총장 117 가슴 100 허리 108 소매 27\u003c/p\u003e"</script>`
    );
    expect(parsed?.rawRows).toEqual([
      ["M", "116", "96", "104", "26"],
      ["L", "117", "100", "108", "27"]
    ]);
  });

  it("preserves measurement rows separated by break tags", () => {
    const parsed = parseMeasurementText(`
      <p>1(M) 어깨48 가슴58 소매61 총장67<br>
      2(L) 어깨50 가슴62 소매63 총장70<br>
      3(XL) 어깨56 가슴69 소매63 총장75</p>
    `);
    expect(parsed?.rawRows).toEqual([
      ["1(M)", "48", "58", "61", "67"],
      ["2(L)", "50", "62", "63", "70"],
      ["3(XL)", "56", "69", "63", "75"]
    ]);
  });

  it("separates size rows collapsed into one hydration string", () => {
    const parsed = parseMeasurementText(
      "1(M) 어깨48 가슴58 소매61 총장67 2(L) 어깨50 가슴62 소매63 총장70 3(XL) 어깨56 가슴69 소매63 총장75"
    );
    expect(parsed?.rawRows).toEqual([
      ["1(M)", "48", "58", "61", "67"],
      ["2(L)", "50", "62", "63", "70"],
      ["3(XL)", "56", "69", "63", "75"]
    ]);
  });

  it("preserves source row and column order while expanding spans and empty cells", () => {
    const table = `
      <table>
        <tr><th rowspan="2">사이즈</th><th colspan="2">실측 (cm)</th><th>소매길이</th></tr>
        <tr><th>총장</th><th>가슴단면</th><th></th></tr>
        <tr><td>S</td><td>68</td><td>54</td><td>22</td></tr>
        <tr><td>M</td><td>70</td><td>56</td><td></td></tr>
      </table>`;
    const parsed = parseBestSizeTable(table);
    expect(parsed?.rawHeaders).toEqual(["사이즈", "총장", "가슴단면", "소매길이"]);
    expect(parsed?.rawRows).toEqual([
      ["S", "68", "54", "22"],
      ["M", "70", "56", ""]
    ]);
  });

  it("distinguishes width, circumference, range, unit conversion, and unknown labels", () => {
    const rows = normalizeSizeTable(
      ["사이즈", "가슴단면", "가슴둘레", "허리", "총장 (cm)"],
      [["FREE", "55", "110", "95~100", "27.5"]],
      "inch"
    );
    expect(rows[0]?.sizeLabel).toBe("FREE");
    expect(rows[0]?.measurements.chestWidth?.measurementType).toBe("width");
    expect(rows[0]?.measurements.chestCircumference?.measurementType).toBe("circumference");
    expect(rows[0]?.measurements.waistWidth?.measurementType).toBe("range");
    expect(rows[0]?.measurements.totalLength?.normalizedValue).toBe(69.85);
  });

  it("does not assume cm when a unit is absent", () => {
    expect(normalizeMeasurement("55", "unknown", "width")).toMatchObject({
      normalizedValue: 55,
      normalizedUnit: "unknown",
      confidence: 0.5
    });
  });

  it("normalizes a transposed size table when measurement labels are row headers", () => {
    const table = `
      <table>
        <tr><th>사이즈</th><th>S</th><th>M</th><th>L</th></tr>
        <tr><th>옷길이</th><td>57</td><td>58.5</td><td>60</td></tr>
        <tr><th>어깨너비</th><td>39</td><td>40.5</td><td>42</td></tr>
        <tr><th>가슴둘레</th><td>94</td><td>99</td><td>106</td></tr>
      </table>`;
    const parsed = parseBestSizeTable(table);
    expect(parsed?.rawHeaders).toEqual(["사이즈", "S", "M", "L"]);
    expect(parsed?.rawRows).toEqual([
      ["옷길이", "57", "58.5", "60"],
      ["어깨너비", "39", "40.5", "42"],
      ["가슴둘레", "94", "99", "106"]
    ]);
    expect(parsed?.normalizedRows).toHaveLength(3);
    expect(parsed?.normalizedRows[1]).toMatchObject({
      sizeLabel: "M",
      measurements: {
        totalLength: { normalizedValue: 58.5 },
        shoulderWidth: { normalizedValue: 40.5 },
        chestCircumference: { normalizedValue: 99 }
      }
    });
  });
});

describe("DOM product and image parsing", () => {
  it("extracts Open Graph data and removes duplicate image variants", () => {
    const html = `
      <meta property="og:title" content="오버핏 셔츠">
      <meta property="og:image" content="https://cdn.example.com/product.jpg?w=500">
      <img src="https://cdn.example.com/product.jpg?w=1000" width="500" height="500">
      <img data-src="https://cdn.example.com/product.jpg?w=1200" width="500" height="500">
      <img src="https://cdn.example.com/size-chart.jpg" alt="사이즈표" width="500" height="500">`;
    const product = extractDomProduct({
      html,
      baseUrl: new URL("https://shop.example.com/item/1"),
      includeImages: true,
      includeDetailImages: false
    });
    expect(product.name).toBe("오버핏 셔츠");
    expect(product.thumbnail).toBe("https://cdn.example.com/product.jpg?w=500");
    expect(product.mainImages).toHaveLength(2);
    expect(product.sizeChartImage).toBe("https://cdn.example.com/size-chart.jpg");
  });
});

describe("Fit Lab URL prefill mapping", () => {
  it("maps a real crawler preview into the existing iOS URL review contract", () => {
    const normalizedRows = normalizeSizeTable(
      ["사이즈", "총장", "어깨너비", "가슴단면", "소매길이"],
      [["M", "70", "48", "58", "61"]],
      "cm"
    );
    const mapped = toFitLabUrlPrefill({
      partial: false,
      source: {
        site: "29cm",
        url: "https://www.29cm.co.kr/products/889486"
      },
      product: {
        name: "Cerritos Sweat-Shirt",
        brand: "HOTEL CERRITOS",
        normalizedCategory: "SWEATSHIRT"
      },
      sizeChart: { normalizedRows }
    });
    expect(mapped).toEqual({
      productName: "Cerritos Sweat-Shirt",
      brand: "HOTEL CERRITOS",
      mallName: "29cm",
      productUrl: "https://www.29cm.co.kr/products/889486",
      category: "sweatshirt",
      fitType: "regular",
      parsingStatus: "parsed",
      sizes: [{
        sizeLabel: "M",
        shoulderWidth: 48,
        chestWidth: 58,
        totalLength: 70,
        sleeveLength: 61,
        waistWidth: null,
        hipWidth: null,
        rise: null,
        outseam: null
      }]
    });
  });
});
