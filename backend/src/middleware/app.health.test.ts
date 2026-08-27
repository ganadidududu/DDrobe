import { createServer } from "node:http";
import type { Server } from "node:http";
import { afterEach, describe, expect, it } from "vitest";
import { app } from "../app";

type RunningServer = {
  readonly port: number;
  readonly server: Server;
};

const startApp = (): Promise<RunningServer> =>
  new Promise((resolve, reject) => {
    const server = createServer(app);
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();

      if (address === null || typeof address === "string") {
        server.close();
        reject(new Error("Expected the health test server to use a TCP address."));
        return;
      }

      resolve({ port: address.port, server });
    });
  });

const stopApp = (server: Server): Promise<void> =>
  new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }

      resolve();
    });
  });

describe("GET /health", () => {
  let runningServer: RunningServer | undefined;

  afterEach(async () => {
    if (runningServer) {
      await stopApp(runningServer.server);
      runningServer = undefined;
    }
  });

  it("returns the backend health contract", async () => {
    // Given: the backend app is listening on an ephemeral local port.
    runningServer = await startApp();

    // When: a client requests the health endpoint.
    const response = await fetch(`http://127.0.0.1:${runningServer.port}/health`);

    // Then: the public status and JSON response identify a healthy backend.
    expect(response.status).toBe(200);
    await expect(response.text()).resolves.toBe(
      '{"ok":true,"service":"coordit-backend"}'
    );
  });

  it("does not grant browser CORS access to an unconfigured origin", async () => {
    // Given: the backend app has only its configured development browser origins.
    runningServer = await startApp();

    // When: a browser request arrives from an origin outside that allowlist.
    const response = await fetch(`http://127.0.0.1:${runningServer.port}/health`, {
      headers: { Origin: "https://untrusted.example" }
    });

    // Then: the HTTP response succeeds but carries no browser-access CORS header.
    expect(response.status).toBe(200);
    expect(response.headers.get("access-control-allow-origin")).toBeNull();
  });

  it("grants browser CORS access to the configured local development origin", async () => {
    // Given: the backend app has localhost:3000 in its development allowlist.
    runningServer = await startApp();

    // When: a browser request arrives from that configured origin.
    const response = await fetch(`http://127.0.0.1:${runningServer.port}/health`, {
      headers: { Origin: "http://localhost:3000" }
    });

    // Then: the HTTP response supplies the exact allowlisted CORS origin.
    expect(response.status).toBe(200);
    expect(response.headers.get("access-control-allow-origin")).toBe("http://localhost:3000");
  });

  it("keeps the health endpoint available without a browser Origin header", async () => {
    // Given: an iOS client sends an API request without a browser Origin header.
    runningServer = await startApp();

    // When: the client requests the health endpoint.
    const response = await fetch(`http://127.0.0.1:${runningServer.port}/health`);

    // Then: the HTTP health contract remains available to the non-browser client.
    expect(response.status).toBe(200);
    await expect(response.text()).resolves.toBe(
      '{"ok":true,"service":"coordit-backend"}'
    );
  });

  it("reaches the AdMob rewarded handler without a bearer token", async () => {
    // Given: AdMob calls the server-side verification URL without application credentials.
    runningServer = await startApp();

    // When: the rewarded callback arrives with its SSV query parameters.
    const response = await fetch(
      `http://127.0.0.1:${runningServer.port}/webhooks/admob/rewarded?user_id=user-1&signature=admob-signature`
    );

    // Then: the public webhook reaches its signature validation instead of auth middleware returning 401.
    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      message: "Invalid AdMob rewarded callback"
    });
  });

  it("serves the public support page without authentication", async () => {
    // Given: the backend app is listening without an authenticated user.
    runningServer = await startApp();

    // When: an App Store visitor requests the support URL.
    const response = await fetch(`http://127.0.0.1:${runningServer.port}/support`);

    // Then: the public HTML contract exposes support and privacy destinations.
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/html; charset=utf-8");
    const body = await response.text();
    expect(body).toContain('href="mailto:insung6853@gmail.com"');
    expect(body).toContain('href="/privacy"');
    expect(body).toContain("word-break: keep-all");
    expect(body).toContain('<span class="nowrap">로그인할 수 있습니다</span>');
  });

  it("serves the public privacy policy without authentication", async () => {
    // Given: the backend app is listening without an authenticated user.
    runningServer = await startApp();

    // When: an App Store visitor requests the privacy-policy URL.
    const response = await fetch(`http://127.0.0.1:${runningServer.port}/privacy`);

    // Then: the public HTML contract exposes its effective date and support channel.
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/html; charset=utf-8");
    const body = await response.text();
    expect(body).toContain('datetime="2026-08-27"');
    expect(body).toContain('href="mailto:insung6853@gmail.com"');
    expect(body).toContain("word-break: keep-all");
    expect(body).toContain('<span class="nowrap">FIT LAB</span>');
    expect(body).toContain('<span class="nowrap">요청할 수 있습니다</span>');
  });
});
