import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { app } from "../../app";
import { supabaseAuth } from "../../config/supabase";

let server: Server;
let baseURL: string;

beforeAll(async () => {
  server = app.listen(0, "127.0.0.1");
  await new Promise<void>((resolve) => server.once("listening", resolve));
  const address = server.address() as AddressInfo;
  baseURL = `http://127.0.0.1:${address.port}`;
});

afterAll(async () => {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => error ? reject(error) : resolve());
  });
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("POST /auth/refresh", () => {
  it("is public and returns a rotated session", async () => {
    vi.spyOn(supabaseAuth.auth, "refreshSession").mockResolvedValue({
      data: {
        user: null,
        session: {
          access_token: "rotated-access-token",
          refresh_token: "rotated-refresh-token",
        },
      },
      error: null,
    } as never);

    const response = await fetch(`${baseURL}/auth/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refreshToken: "saved-refresh-token" }),
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      accessToken: "rotated-access-token",
      refreshToken: "rotated-refresh-token",
    });
  });

  it("rejects a missing refresh token before calling Supabase", async () => {
    const refreshSession = vi.spyOn(supabaseAuth.auth, "refreshSession");

    const response = await fetch(`${baseURL}/auth/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({}),
    });

    expect(response.status).toBe(400);
    expect(refreshSession).not.toHaveBeenCalled();
  });
});
