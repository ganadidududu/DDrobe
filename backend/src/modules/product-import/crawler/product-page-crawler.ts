import { errors as playwrightErrors } from "playwright";
import { env } from "../../../config/env";
import { normalizeCategory } from "../normalization/product-normalizer";
import { ProductImportError } from "../product-import.error";
import type { ProductCrawlContext, ProductImportPreview, ProductSite } from "../product-import.types";
import { browserManager } from "./browser-manager";
import { extractDomProduct } from "./dom-parser";
import { NetworkJsonObserver } from "./network-json-observer";
import {
  extractSizeChartFromUnknown,
  extractSizeChartImageFromUnknown,
  type ParsedTextSizeTable
} from "./size-chart-parser";
import {
  extractProductFromUnknown,
  extractStructuredProduct,
  type ExtractedProductData
} from "./structured-data-parser";

const firstNetworkProduct = (candidates: readonly unknown[]): ExtractedProductData | null => {
  for (const candidate of candidates) {
    const product = extractProductFromUnknown(candidate);
    if (product?.name) return product;
  }
  return null;
};

const firstNetworkSizeTable = (candidates: readonly unknown[]): ParsedTextSizeTable | null => {
  const charts = candidates
    .map(extractSizeChartFromUnknown)
    .filter((chart): chart is ParsedTextSizeTable => chart !== null);
  return charts.sort((left, right) => right.rawRows.length - left.rawRows.length)[0] ?? null;
};

const firstNetworkSizeImage = (candidates: readonly unknown[]): string | null => {
  for (const candidate of candidates) {
    const image = extractSizeChartImageFromUnknown(candidate);
    if (image) return image;
  }
  return null;
};

const productIdFromUrl = (url: URL): string | null => {
  const values = [...url.pathname.split("/"), ...url.searchParams.values()];
  for (let index = values.length - 1; index >= 0; index -= 1) {
    const value = values[index];
    if (value && /^\d{4,}$/.test(value)) return value;
  }
  return null;
};

const fetchMusinsaSizeCandidate = async (
  page: import("playwright").Page,
  productUrl: URL
): Promise<unknown | null> => {
  const productId = productIdFromUrl(productUrl);
  if (!productId) return null;
  try {
    const response = await page.context().request.get(
      `https://goods-detail.musinsa.com/api2/goods/${productId}/actual-size`,
      { timeout: Math.min(env.crawlTimeoutMs, 10_000) }
    );
    if (!response.ok()) return null;
    return await response.json();
  } catch {
    return null;
  }
};

export const navigationWaitUntil = (site: ProductSite): "commit" | "domcontentloaded" =>
  site === "musinsa" ? "commit" : "domcontentloaded";

export const shouldRevealSizeContent = (site: ProductSite): boolean => site !== "musinsa";

const resolvePublicImages = (images: readonly string[], baseUrl: URL): readonly string[] => {
  const resolved: string[] = [];
  for (const image of images) {
    try {
      const url = new URL(image, baseUrl);
      if (url.protocol === "http:" || url.protocol === "https:") resolved.push(url.href);
    } catch (error) {
      if (!(error instanceof TypeError)) throw error;
    }
  }
  return resolved;
};

const revealSizeContent = async (page: import("playwright").Page): Promise<void> => {
  const controls = page.locator("button:visible, [role='button']:visible, [role='tab']:visible, a:visible").filter({
    hasText: /사이즈\s*(정보|표|가이드)?|실측|상품\s*정보|상세\s*정보|SIZE\s*(INFO|GUIDE|CHART)?|MEASUREMENTS?/i
  });
  try {
    await controls.first().waitFor({ state: "visible", timeout: Math.min(env.pageLoadTimeoutMs, 15_000) });
  } catch (error) {
    if (error instanceof playwrightErrors.TimeoutError) return;
    throw error;
  }
  const count = Math.min(await controls.count(), 3);
  for (let index = 0; index < count; index += 1) {
    const control = controls.nth(index);
    if (await control.isVisible()) {
      try {
        await control.click({ timeout: 1_000 });
      } catch (error) {
        if (!(error instanceof playwrightErrors.TimeoutError)) throw error;
      }
    }
  }
  try {
    await page.locator("table:visible").first().waitFor({ state: "visible", timeout: 5_000 });
  } catch (error) {
    if (!(error instanceof playwrightErrors.TimeoutError)) throw error;
  }
};

const navigationError = (error: unknown, blocked: ProductImportError | null): ProductImportError => {
  if (blocked) return blocked;
  if (error instanceof playwrightErrors.TimeoutError) {
    return new ProductImportError("CRAWL_TIMEOUT", "상품 페이지 분석 시간이 초과되었습니다.", true, 504);
  }
  return new ProductImportError("PRODUCT_PAGE_NOT_ACCESSIBLE", "상품 페이지에 접근할 수 없습니다.", true, 502);
};

export const crawlProductPage = async (
  context: ProductCrawlContext,
  site: ProductSite
): Promise<ProductImportPreview> => {
  const session = await browserManager.createSession();
  const observer = new NetworkJsonObserver();
  observer.attach(session.page);
  try {
    session.page.setDefaultTimeout(env.crawlTimeoutMs);
    session.page.setDefaultNavigationTimeout(env.pageLoadTimeoutMs);
    let response;
    try {
      response = await session.page.goto(context.url.href, { waitUntil: navigationWaitUntil(site) });
    } catch (error) {
      throw navigationError(error, session.blockedError());
    }
    const blocked = session.blockedError();
    if (blocked) throw blocked;
    if (!response) {
      throw new ProductImportError("PRODUCT_PAGE_NOT_ACCESSIBLE", "상품 페이지에 접근할 수 없습니다.", true, 502);
    }
    if (response.status() === 404) {
      throw new ProductImportError("PRODUCT_NOT_FOUND", "상품을 찾을 수 없습니다.", false, 404);
    }
    if (response.status() === 429) {
      throw new ProductImportError("RATE_LIMITED", "쇼핑몰 요청 한도를 초과했습니다.", true, 429);
    }
    if (response.status() === 401 || response.status() === 403) {
      throw new ProductImportError("SITE_BLOCKED_REQUEST", "쇼핑몰이 페이지 요청을 차단했습니다.", true, 502);
    }
    if (site === "musinsa") {
      const responseError = await response.finished();
      if (responseError) throw navigationError(responseError, session.blockedError());
    }
    if (shouldRevealSizeContent(site)) await revealSizeContent(session.page);
    const html = await session.page.content();
    if (Buffer.byteLength(html, "utf8") > env.maxHtmlBytes) {
      throw new ProductImportError("RESPONSE_TOO_LARGE", "상품 페이지 응답이 너무 큽니다.", false, 413);
    }
    await observer.settle();
    const musinsaSizeCandidate = site === "musinsa"
      ? await fetchMusinsaSizeCandidate(session.page, context.url)
      : null;
    const networkCandidates = [
      ...(musinsaSizeCandidate ? [musinsaSizeCandidate] : []),
      ...observer.getCandidates()
    ];
    const structured = extractStructuredProduct(html);
    const network = firstNetworkProduct(networkCandidates);
    const networkSizeTable = firstNetworkSizeTable(networkCandidates);
    const dom = extractDomProduct({
      html,
      baseUrl: context.url,
      includeImages: context.includeImages,
      includeDetailImages: context.includeDetailImages
    });
    const name = structured?.name ?? network?.name ?? dom.name;
    if (!name) {
      throw new ProductImportError("PRODUCT_NAME_NOT_FOUND", "상품명을 찾을 수 없습니다.", false, 422);
    }
    const brand = structured?.brand ?? network?.brand ?? dom.brand;
    const rawCategory = structured?.category ?? network?.category ?? dom.category;
    const description = structured?.description ?? network?.description ?? dom.description;
    const sizeTable = dom.sizeTable ?? networkSizeTable;
    const sizeChartImage = context.includeImages
      ? dom.sizeChartImage ?? firstNetworkSizeImage(networkCandidates)
      : null;
    const warnings: string[] = [];
    if (!sizeTable) warnings.push("상품명은 추출했지만 사이즈표를 찾지 못했습니다.");
    if (observer.exceededLimit()) warnings.push("크기가 큰 네트워크 JSON 응답은 분석에서 제외했습니다.");
    if (sizeChartImage && !sizeTable) warnings.push("이미지형 사이즈표가 감지되어 OCR 또는 사용자 확인이 필요합니다.");
    const methods = [
      ...(structured ? ["structured-data" as const] : []),
      ...(network || networkSizeTable || sizeChartImage ? ["network-json" as const] : []),
      "dom" as const
    ];
    const mainImages = context.includeImages
      ? [...new Set([
        ...resolvePublicImages(structured?.images ?? [], context.url),
        ...resolvePublicImages(network?.images ?? [], context.url),
        ...dom.mainImages
      ])]
      : [];
    return {
      success: true,
      partial: !sizeTable,
      source: {
        site,
        url: context.url.href,
        productId: structured?.productId ?? network?.productId ?? productIdFromUrl(context.url),
        crawledAt: context.crawledAt
      },
      product: {
        name,
        brand,
        rawCategory,
        normalizedCategory: normalizeCategory([rawCategory, name, description].filter(Boolean).join(" ")),
        price: structured?.price || network?.price ? {
          original: structured?.price ?? network?.price ?? null,
          sale: null,
          currency: structured?.currency ?? network?.currency ?? null
        } : null,
        gender: null,
        materials: [],
        description,
        soldOut: null
      },
      images: {
        thumbnail: context.includeImages ? dom.thumbnail ?? mainImages[0] ?? null : null,
        main: mainImages.slice(0, env.maxImages),
        detail: dom.detailImages,
        sizeChartImage
      },
      options: {
        colors: [...new Set([...(structured?.colors ?? []), ...(network?.colors ?? [])])],
        sizes: [...new Set([
          ...(structured?.sizes ?? []),
          ...(network?.sizes ?? []),
          ...(sizeTable?.normalizedRows.map((row) => row.sizeLabel) ?? [])
        ])]
      },
      sizeChart: {
        found: Boolean(sizeTable),
        type: sizeTable ? "productMeasurement" : null,
        unit: sizeTable?.unit ?? "unknown",
        rawHeaders: sizeTable?.rawHeaders ?? [],
        rawRows: sizeTable?.rawRows ?? [],
        normalizedRows: sizeTable?.normalizedRows ?? [],
        notes: [],
        requiresOcr: Boolean(sizeChartImage && !sizeTable),
        ocrAvailable: false
      },
      metadata: {
        adapter: site,
        extractionMethods: methods,
        confidence: sizeTable ? 0.9 : 0.55,
        warnings,
        fieldSources: {
          "product.name": {
            method: structured?.name ? "structured-data" : network?.name ? "network-json" : "dom",
            confidence: structured?.name ? 0.99 : network?.name ? 0.9 : 0.75
          },
          ...(brand ? {
            "product.brand": {
              method: structured?.brand ? "structured-data" as const : network?.brand ? "network-json" as const : "dom" as const,
              confidence: structured?.brand ? 0.98 : network?.brand ? 0.88 : 0.7
            }
          } : {}),
          ...(sizeTable ? {
            sizeChart: {
              method: dom.sizeTable ? "dom" as const : "network-json" as const,
              confidence: dom.sizeTable ? 0.9 : 0.85
            }
          } : {})
        }
      }
    };
  } finally {
    await session.close();
  }
};
