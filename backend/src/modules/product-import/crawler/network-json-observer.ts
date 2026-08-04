import type { Page, Response } from "playwright";
import { env } from "../../../config/env";

const CANDIDATE_URL =
  /product|goods|item|option|variant|size|measurement|dimension|specification|catalog|detail|information|graphql|pdp/i;

export class NetworkJsonObserver {
  private readonly candidates: unknown[] = [];
  private readonly pending = new Set<Promise<void>>();
  private tooLarge = false;

  public attach(page: Page): void {
    page.on("response", (response) => {
      const task = this.inspect(response)
        .catch((error: unknown) => {
          if (isExpectedBrowserTeardown(error)) return;
          console.warn("Unable to inspect product import network response", error);
        })
        .finally(() => this.pending.delete(task));
      this.pending.add(task);
    });
  }

  private async inspect(response: Response): Promise<void> {
    if (!CANDIDATE_URL.test(response.url())) return;
    try {
      const headers = await response.allHeaders();
      if (!headers["content-type"]?.toLowerCase().includes("json")) return;
      const declaredLength = Number(headers["content-length"] ?? "0");
      if (declaredLength > env.maxJsonResponseBytes) {
        this.tooLarge = true;
        return;
      }
      const body = await response.body();
      if (body.byteLength > env.maxJsonResponseBytes) {
        this.tooLarge = true;
        return;
      }
      const parsed: unknown = JSON.parse(body.toString("utf8"));
      if (this.candidates.length < 20) this.candidates.push(parsed);
    } catch (error) {
      if (error instanceof SyntaxError || isExpectedBrowserTeardown(error)) return;
      throw error;
    }
  }

  public async settle(): Promise<void> {
    await Promise.all([...this.pending]);
  }

  public getCandidates(): readonly unknown[] {
    return this.candidates;
  }

  public exceededLimit(): boolean {
    return this.tooLarge;
  }
}

const isExpectedBrowserTeardown = (error: unknown): boolean =>
  error instanceof Error && /closed|failed|body/i.test(error.message);
