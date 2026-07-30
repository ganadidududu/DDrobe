import { describe, expect, it } from "vitest";
import { NetworkJsonObserver } from "../crawler/network-json-observer";

type ResponseHandler = (response: {
  url: () => string;
  allHeaders: () => Promise<Record<string, string>>;
  body: () => Promise<Buffer>;
}) => void;

class FakePage {
  private responseHandler: ResponseHandler | undefined;

  public on(event: "response", handler: ResponseHandler): void {
    if (event === "response") this.responseHandler = handler;
  }

  public emitLateResponse(): void {
    this.responseHandler?.({
      url: () => "https://shop.example.com/product/late-response",
      allHeaders: async () => {
        throw new Error("Target page, context or browser has been closed");
      },
      body: async () => Buffer.from("{}")
    });
  }
}

describe("NetworkJsonObserver", () => {
  it("settles safely when a response arrives after page teardown", async () => {
    const page = new FakePage();
    const observer = new NetworkJsonObserver();
    observer.attach(page as never);

    await observer.settle();
    page.emitLateResponse();

    await new Promise((resolve) => setTimeout(resolve, 0));
    await expect(observer.settle()).resolves.toBeUndefined();
  });
});
