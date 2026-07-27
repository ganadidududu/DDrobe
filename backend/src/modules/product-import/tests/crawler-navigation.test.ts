import { describe, expect, it } from "vitest";
import {
  navigationWaitUntil,
  shouldRevealSizeContent
} from "../crawler/product-page-crawler";

describe("product crawler navigation readiness", () => {
  it("does not wait for Musinsa lifecycle events after the committed document is usable", () => {
    expect(navigationWaitUntil("musinsa")).toBe("commit");
    expect(shouldRevealSizeContent("musinsa")).toBe(false);
    expect(navigationWaitUntil("generic")).toBe("domcontentloaded");
    expect(shouldRevealSizeContent("generic")).toBe(true);
  });
});
