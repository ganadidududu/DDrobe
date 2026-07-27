import { crawlProductPage } from "../crawler/product-page-crawler";
import type {
  ProductCrawlContext,
  ProductCrawlerAdapter,
  ProductImportPreview,
  ProductSite
} from "../product-import.types";

abstract class DomainAdapter implements ProductCrawlerAdapter {
  public abstract readonly name: ProductSite;
  protected abstract readonly domains: readonly string[];

  public supports(url: URL): boolean {
    const hostname = url.hostname.toLowerCase();
    return this.domains.some((domain) => hostname === domain || hostname.endsWith(`.${domain}`));
  }

  public extract(context: ProductCrawlContext): Promise<ProductImportPreview> {
    return crawlProductPage(context, this.name);
  }
}

export class MusinsaAdapter extends DomainAdapter {
  public readonly name = "musinsa" as const;
  protected readonly domains = ["musinsa.com"] as const;
}

export class TwentyNineCmAdapter extends DomainAdapter {
  public readonly name = "29cm" as const;
  protected readonly domains = ["29cm.co.kr"] as const;
}

export class AblyAdapter extends DomainAdapter {
  public readonly name = "ably" as const;
  protected readonly domains = ["a-bly.com"] as const;
}

export const toWConceptMobileUrl = (url: URL): URL => {
  if (!/^\/product\/\d+/i.test(url.pathname)) return url;
  const mobileUrl = new URL(url);
  mobileUrl.hostname = "m.wconcept.co.kr";
  return mobileUrl;
};

export class WConceptAdapter extends DomainAdapter {
  public readonly name = "wconcept" as const;
  protected readonly domains = ["wconcept.co.kr"] as const;

  public override async extract(context: ProductCrawlContext): Promise<ProductImportPreview> {
    const preview = await crawlProductPage({
      ...context,
      url: toWConceptMobileUrl(context.url)
    }, this.name);
    return {
      ...preview,
      source: {
        ...preview.source,
        url: context.url.href
      }
    };
  }
}

export class NaverSmartStoreAdapter extends DomainAdapter {
  public readonly name = "naver-smart-store" as const;
  protected readonly domains = ["smartstore.naver.com", "brand.naver.com"] as const;
}

export class ZigzagAdapter extends DomainAdapter {
  public readonly name = "zigzag" as const;
  protected readonly domains = ["zigzag.kr"] as const;
}

export class GenericFashionStoreAdapter implements ProductCrawlerAdapter {
  public readonly name = "generic" as const;

  public supports(_url: URL): boolean {
    return true;
  }

  public extract(context: ProductCrawlContext): Promise<ProductImportPreview> {
    return crawlProductPage(context, this.name);
  }
}

export const productCrawlerAdapters: readonly ProductCrawlerAdapter[] = [
  new MusinsaAdapter(),
  new TwentyNineCmAdapter(),
  new AblyAdapter(),
  new WConceptAdapter(),
  new NaverSmartStoreAdapter(),
  new ZigzagAdapter()
];

export const genericFashionStoreAdapter = new GenericFashionStoreAdapter();
