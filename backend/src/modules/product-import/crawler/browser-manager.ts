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

export const isBrowserClosedError = (error: unknown): boolean =>
  error instanceof Error && /target page, context or browser has been closed/i.test(error.message);

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

export class BrowserManager {
  private browserPromise: Promise<Browser> | null = null;
  private readonly semaphore = new PageSemaphore();

  private launchBrowser(): Promise<Browser> {
    const browserPromise = chromium.launch({ headless: true });
    this.browserPromise = browserPromise;
    void browserPromise.then(
      (browser) => {
        browser.once("disconnected", () => {
          if (this.browserPromise === browserPromise) this.browserPromise = null;
        });
      },
      () => {
        if (this.browserPromise === browserPromise) this.browserPromise = null;
      }
    );
    return browserPromise;
  }

  private async getBrowser(): Promise<Browser> {
    const browserPromise = this.browserPromise ?? this.launchBrowser();
    const browser = await browserPromise;
    if (browser.isConnected()) return browser;
    if (this.browserPromise === browserPromise) this.browserPromise = null;
    return this.getBrowser();
  }

  private createContext(browser: Browser): Promise<BrowserContext> {
    return browser.newContext({
      acceptDownloads: false,
      userAgent: env.crawlerUserAgent,
      serviceWorkers: "block"
    });
  }

  private async createRecoverableContext(): Promise<BrowserContext> {
    const browserPromise = this.browserPromise ?? this.launchBrowser();
    const browser = await browserPromise;
    try {
      return await this.createContext(browser);
    } catch (error) {
      const needsReplacement = isBrowserClosedError(error) || !browser.isConnected();
      if (!needsReplacement) throw error;
      if (this.browserPromise === browserPromise) this.browserPromise = null;
      if (browser.isConnected()) {
        try {
          await browser.close();
        } catch (closeError) {
          if (!isBrowserClosedError(closeError)) throw closeError;
        }
      }
      return this.createContext(await this.getBrowser());
    }
  }

  public async close(): Promise<void> {
    const browserPromise = this.browserPromise;
    if (!browserPromise) return;
    const browser = await browserPromise;
    if (browser.isConnected()) await browser.close();
  }

  public async createSession(): Promise<BrowserSession> {
    const release = await this.semaphore.acquire();
    try {
      const context = await this.createRecoverableContext();
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
