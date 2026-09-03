import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { app } from "../../app";
import { supabaseAdmin, supabaseAuth } from "../../config/supabase";

const appleUser = {
  id: "apple-user-1",
  email: "mina@privaterelay.appleid.com"
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

const mockProfileUpsert = () => {
  const single = vi.fn().mockResolvedValue({ data: appleUser, error: null });
  const select = vi.fn().mockReturnValue({ single });
  const upsert = vi.fn().mockReturnValue({ select });
  vi.spyOn(supabaseAdmin, "from").mockReturnValue({ upsert } as never);
  return { upsert };
};

describe("POST /auth/apple", () => {
  it("forwards the submitted Apple identity token and nonce to the production Supabase adapter", async () => {
    const signInWithIdToken = vi.spyOn(supabaseAuth.auth, "signInWithIdToken").mockResolvedValue({
      data: {
        user: appleUser,
        session: {
          access_token: "apple-access-token",
          refresh_token: "apple-refresh-token"
        }
      },
      error: null
    } as never);
    const { upsert } = mockProfileUpsert();

    const response = await fetch(`${baseURL}/auth/apple`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ idToken: " apple-id-token ", nonce: " raw-apple-nonce " })
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      accessToken: "apple-access-token",
      refreshToken: "apple-refresh-token",
      user: { ...appleUser, isAnonymous: false }
    });
    expect(signInWithIdToken).toHaveBeenCalledWith({
      provider: "apple",
      token: "apple-id-token",
      nonce: "raw-apple-nonce"
    });
    expect(upsert).toHaveBeenCalledOnce();
  });

  it("rejects incomplete Apple credentials before calling Supabase", async () => {
    const signInWithIdToken = vi.spyOn(supabaseAuth.auth, "signInWithIdToken");

    const response = await fetch(`${baseURL}/auth/apple`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ idToken: "apple-id-token" })
    });

    expect(response.status).toBe(400);
    expect(signInWithIdToken).not.toHaveBeenCalled();
  });
});
