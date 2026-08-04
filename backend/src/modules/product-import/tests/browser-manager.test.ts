import { describe, expect, it, vi } from "vitest";
import { BrowserManager, browserManager, isBrowserClosedError } from "../crawler/browser-manager";
import { crawlProductPage } from "../crawler/product-page-crawler";

describe("BrowserManager", () => {
  it("recognizes a target-closed context creation failure as recoverable", () => {
    expect(isBrowserClosedError(new Error("Target page, context or browser has been closed"))).toBe(true);
    expect(isBrowserClosedError(new Error("Protocol error: other failure"))).toBe(false);
  });

  it("starts a fresh browser after the cached browser closes", async () => {
    const manager = new BrowserManager();
    try {
      const firstSession = await manager.createSession();
      await firstSession.close();
      await manager.close();

      const recoveredSession = await manager.createSession();
      expect(recoveredSession.page.isClosed()).toBe(false);
      await recoveredSession.close();
    } finally {
      await manager.close();
    }
  });
});

describe("crawlProductPage", () => {
  it("converts browser session startup failures into a retryable product-import error", async () => {
    const createSession = vi.spyOn(browserManager, "createSession")
      .mockRejectedValue(new Error("Target page, context or browser has been closed"));
    try {
      await expect(crawlProductPage({
        url: new URL("https://www.musinsa.com/products/6252903"),
        includeImages: false,
        includeDetailImages: false,
        crawledAt: "2026-07-31T00:00:00.000Z"
      }, "musinsa")).rejects.toMatchObject({
        code: "PRODUCT_PAGE_NOT_ACCESSIBLE",
        message: "상품 페이지에 접근할 수 없습니다.",
        retryable: true,
        statusCode: 502
      });
    } finally {
      createSession.mockRestore();
    }
  });
});
