import { env } from "../../config/env";
import {
  genericFashionStoreAdapter,
  productCrawlerAdapters
} from "./adapters/product-crawler-adapters";
import { ProductImportError } from "./product-import.error";
import type { ProductImportRequest } from "./product-import.schemas";
import type { ProductImportPreview } from "./product-import.types";
import { assertPublicUrl, normalizeProductUrl, parseProductUrl } from "./security/url-validator";

const requestTimes = new Map<string, number[]>();
const lastDomainRequest = new Map<string, number>();
const domainQueues = new Map<string, Promise<void>>();

const enforceUserRateLimit = (userId: string, now: number): void => {
  const recent = (requestTimes.get(userId) ?? []).filter((timestamp) => now - timestamp < 60_000);
  if (recent.length >= env.userRateLimitPerMinute) {
    throw new ProductImportError("RATE_LIMITED", "잠시 후 다시 시도해주세요.", true, 429);
  }
  requestTimes.set(userId, [...recent, now]);
};

const delayForDomain = async (hostname: string): Promise<void> => {
  const previous = domainQueues.get(hostname) ?? Promise.resolve();
  const next = previous.then(async () => {
    const delay = Math.max(
      0,
      (lastDomainRequest.get(hostname) ?? 0) + env.domainRequestDelayMs - Date.now()
    );
    if (delay > 0) await new Promise<void>((resolve) => setTimeout(resolve, delay));
    lastDomainRequest.set(hostname, Date.now());
  });
  domainQueues.set(hostname, next);
  await next;
  if (domainQueues.get(hostname) === next) domainQueues.delete(hostname);
};

export const previewProductImport = async (
  userId: string,
  request: ProductImportRequest
): Promise<ProductImportPreview> => {
  enforceUserRateLimit(userId, Date.now());
  const parsedUrl = parseProductUrl(request.url);
  await assertPublicUrl(parsedUrl);
  const normalizedUrl = new URL(normalizeProductUrl(parsedUrl));
  await delayForDomain(normalizedUrl.hostname);
  const adapter = productCrawlerAdapters.find((candidate) => candidate.supports(normalizedUrl))
    ?? genericFashionStoreAdapter;
  return adapter.extract({
    url: normalizedUrl,
    includeImages: request.includeImages,
    includeDetailImages: request.includeDetailImages,
    crawledAt: new Date().toISOString()
  });
};
