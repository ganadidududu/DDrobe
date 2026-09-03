import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { app } from "../../app";
import { supabaseAdmin, supabaseAuth } from "../../config/supabase";

let server: Server;
let baseURL: string;

beforeAll(async () => {
  server = app.listen(0, "127.0.0.1");
  await new Promise<void>((resolve) => server.once("listening", resolve));
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("Test server address is unavailable");
  baseURL = `http://127.0.0.1:${(address satisfies AddressInfo).port}`;
});

afterAll(async () => {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => error ? reject(error) : resolve());
  });
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("POST /auth/guest", () => {
  it("creates an anonymous authenticated session without collecting personal information", async () => {
    // Given
    const userId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    vi.spyOn(supabaseAuth.auth, "signInAnonymously").mockResolvedValue({
      data: {
        user: { id: userId, is_anonymous: true },
        session: {
          access_token: "guest-access-token",
          refresh_token: "guest-refresh-token",
        },
      },
      error: null,
    } as never);
    const single = vi.fn().mockResolvedValue({ data: { id: userId }, error: null });
    const select = vi.fn().mockReturnValue({ single });
    const upsert = vi.fn().mockReturnValue({ select });
    vi.spyOn(supabaseAdmin, "from").mockReturnValue({ upsert } as never);

    // When
    const response = await fetch(`${baseURL}/auth/guest`, { method: "POST" });

    // Then
    expect(response.status).toBe(201);
    expect(await response.json()).toEqual({
      accessToken: "guest-access-token",
      refreshToken: "guest-refresh-token",
      user: {
        id: userId,
        email: `guest+${userId}@guest.coordit.invalid`,
        isAnonymous: true,
      },
    });
    expect(upsert).toHaveBeenCalledOnce();
  });
});
