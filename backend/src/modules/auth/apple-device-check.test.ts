import { generateKeyPairSync } from "node:crypto";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { createAppleDeviceWelcomeRegistry } from "./apple-device-check";

let server: Server;
let baseURL: string;
const requestPaths: string[] = [];
let queryFailureStatus: number | null = null;
let queryResponseBody = JSON.stringify({ bit0: false, bit1: false });

beforeAll(async () => {
  server = createServer((request, response) => {
    requestPaths.push(request.url ?? "");
    if (request.url === "/v1/query_two_bits") {
      response.setHeader("Content-Type", "application/json");
      if (queryFailureStatus !== null) {
        response.statusCode = queryFailureStatus;
        response.end(JSON.stringify({ error: "Bad Device Token" }));
        return;
      }
      response.end(queryResponseBody);
      return;
    }
    response.statusCode = 200;
    response.end();
  });
  server.listen(0, "127.0.0.1");
  await new Promise<void>((resolve) => server.once("listening", resolve));
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("Test server address is unavailable");
  baseURL = `http://127.0.0.1:${(address satisfies AddressInfo).port}`;
});

beforeEach(() => {
  requestPaths.length = 0;
  queryFailureStatus = null;
  queryResponseBody = JSON.stringify({ bit0: false, bit1: false });
});

afterAll(async () => {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => error ? reject(error) : resolve());
  });
});

describe("Apple DeviceCheck welcome registry", () => {
  it("queries and marks the persistent promotion bit", async () => {
    // Given
    const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
    const registry = createAppleDeviceWelcomeRegistry({
      keyId: "DEVICECHECK_KEY",
      teamId: "87V7WR9QND",
      privateKey: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
      environment: "development",
      baseURL,
    });

    // When
    const claimed = await registry.hasClaimedWelcome("device-token");
    await registry.markWelcomeClaimed("device-token");

    // Then
    expect(claimed).toBe(false);
    expect(requestPaths).toEqual(["/v1/query_two_bits", "/v1/update_two_bits"]);
  });

  it("reports Apple's safe error code when a DeviceCheck request fails", async () => {
    // Given
    const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
    queryFailureStatus = 400;
    const registry = createAppleDeviceWelcomeRegistry({
      keyId: "DEVICECHECK_KEY",
      teamId: "87V7WR9QND",
      privateKey: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
      environment: "development",
      baseURL,
    });

    // When / Then
    await expect(registry.hasClaimedWelcome("device-token")).rejects.toMatchObject({
      message: "DeviceCheck query_two_bits failed (400): Bad Device Token",
      statusCode: 502,
    });
  });

  it("treats Apple's missing bit state response as an unused device", async () => {
    // Given
    const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
    queryResponseBody = "Failed to find bit state";
    const registry = createAppleDeviceWelcomeRegistry({
      keyId: "DEVICECHECK_KEY",
      teamId: "87V7WR9QND",
      privateKey: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
      environment: "development",
      baseURL,
    });

    // When / Then
    await expect(registry.hasClaimedWelcome("device-token")).resolves.toBe(false);
  });
});
