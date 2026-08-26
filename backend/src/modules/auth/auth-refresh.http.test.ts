import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { app } from "../../app";
import { supabaseAdmin, supabaseAuth } from "../../config/supabase";

const refreshedUser = {
  id: "returning-user-1",
  email: "returning@example.com"
};

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
  it("rotates a stored refresh token without requiring the social provider again", async () => {
    const refreshSession = vi.spyOn(supabaseAuth.auth, "refreshSession").mockResolvedValue({
      data: {
        user: refreshedUser,
        session: {
          access_token: "rotated-access-token",
          refresh_token: "rotated-refresh-token"
        }
      },
      error: null
    } as never);
    const single = vi.fn().mockResolvedValue({ data: refreshedUser, error: null });
    const select = vi.fn().mockReturnValue({ single });
    const upsert = vi.fn().mockReturnValue({ select });
    vi.spyOn(supabaseAdmin, "from").mockReturnValue({ upsert } as never);

    const response = await fetch(`${baseURL}/auth/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refreshToken: " stored-refresh-token " })
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      accessToken: "rotated-access-token",
      refreshToken: "rotated-refresh-token",
      user: refreshedUser
    });
    expect(refreshSession).toHaveBeenCalledWith({ refresh_token: "stored-refresh-token" });
  });

  it("rejects an empty refresh token before calling Supabase", async () => {
    const refreshSession = vi.spyOn(supabaseAuth.auth, "refreshSession");
    const response = await fetch(`${baseURL}/auth/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refreshToken: " " })
    });

    expect(response.status).toBe(400);
    expect(refreshSession).not.toHaveBeenCalled();
  });
});
