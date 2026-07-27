import { chromium, type Browser, type BrowserContext, type Page, type Route } from "playwright";
import { env } from "../../../config/env";
import { ProductImportError } from "../product-import.error";
import { assertPublicUrl, parseProductUrl } from "../security/url-validator";

export type BrowserSession = {
  readonly context: BrowserContext;
  readonly page: Page;
  readonly blockedError: () => ProductImportError | null;
  readonly close: () => Promise<void>;
};

class PageSemaphore {
  private active = 0;
  private readonly waiters: Array<() => void> = [];

  public async acquire(): Promise<() => void> {
    if (this.active >= env.maxConcurrentPages) {
      await new Promise<void>((resolve) => this.waiters.push(resolve));
    }
    this.active += 1;
    return () => {
      this.active -= 1;
      this.waiters.shift()?.();
    };
  }
}

class BrowserManager {
  private browserPromise: Promise<Browser> | null = null;
  private readonly semaphore = new PageSemaphore();

  private getBrowser(): Promise<Browser> {
    this.browserPromise ??= chromium.launch({ headless: true });
    return this.browserPromise;
  }

  public async createSession(): Promise<BrowserSession> {
    const release = await this.semaphore.acquire();
    try {
      const browser = await this.getBrowser();
      const context = await browser.newContext({
        acceptDownloads: false,
        userAgent: env.crawlerUserAgent,
        serviceWorkers: "block"
      });
      const page = await context.newPage();
      let blocked: ProductImportError | null = null;
      const publicHostChecks = new Map<string, Promise<void>>();
      await context.route("**/*", async (route: Route) => {
        const request = route.request();
        const requestUrl = request.url();
        if (requestUrl.startsWith("data:") || requestUrl.startsWith("blob:")) {
          await route.continue();
          return;
        }
        try {
          const target = parseProductUrl(requestUrl);
          const hostKey = `${target.protocol}//${target.hostname}:${target.port}`;
          let publicHostCheck = publicHostChecks.get(hostKey);
          if (!publicHostCheck) {
            publicHostCheck = assertPublicUrl(target);
            publicHostChecks.set(hostKey, publicHostCheck);
          }
          await publicHostCheck;
          let redirects = 0;
          for (let previous = request.redirectedFrom(); previous; previous = previous.redirectedFrom()) redirects += 1;
          if (redirects > env.maxRedirects) {
            blocked = new ProductImportError("SITE_BLOCKED_REQUEST", "리다이렉트 횟수가 너무 많습니다.", false, 400);
            await route.abort("blockedbyclient");
            return;
          }
          await route.continue();
        } catch (error) {
          blocked = error instanceof ProductImportError
            ? error
            : new ProductImportError("SITE_BLOCKED_REQUEST", "안전하지 않은 페이지 요청을 차단했습니다.", false, 400);
          await route.abort("blockedbyclient");
        }
      });
      page.on("popup", (popup) => {
        void popup.close();
      });
      return {
        context,
        page,
        blockedError: () => blocked,
        close: async () => {
          await context.close();
          release();
        }
      };
    } catch (error) {
      release();
      throw error;
    }
  }
}

export const browserManager = new BrowserManager();
