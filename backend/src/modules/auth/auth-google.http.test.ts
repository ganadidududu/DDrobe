import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { app } from "../../app";
import { supabaseAdmin, supabaseAuth } from "../../config/supabase";

const googleUser = {
  id: "google-user-1",
  email: "mina@example.com"
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
  const single = vi.fn().mockResolvedValue({ data: googleUser, error: null });
  const select = vi.fn().mockReturnValue({ single });
  const upsert = vi.fn().mockReturnValue({ select });
  vi.spyOn(supabaseAdmin, "from").mockReturnValue({ upsert } as never);
  return { upsert };
};

describe("POST /auth/google", () => {
  it("forwards the submitted Google identity token and nonce to the production Supabase adapter", async () => {
    const signInWithIdToken = vi.spyOn(supabaseAuth.auth, "signInWithIdToken").mockResolvedValue({
      data: {
        user: googleUser,
        session: {
          access_token: "google-access-token",
          refresh_token: "google-refresh-token"
        }
      },
      error: null
    } as never);
    const { upsert } = mockProfileUpsert();

    const response = await fetch(`${baseURL}/auth/google`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ idToken: " google-id-token ", nonce: " raw-google-nonce " })
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      accessToken: "google-access-token",
      refreshToken: "google-refresh-token",
      user: googleUser
    });
    expect(signInWithIdToken).toHaveBeenCalledWith({
      provider: "google",
      token: "google-id-token",
      nonce: "raw-google-nonce"
    });
    expect(upsert).toHaveBeenCalledOnce();
  });

  it("rejects incomplete Google credentials before calling Supabase", async () => {
    const signInWithIdToken = vi.spyOn(supabaseAuth.auth, "signInWithIdToken");

    const response = await fetch(`${baseURL}/auth/google`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ idToken: "google-id-token" })
    });

    expect(response.status).toBe(400);
    expect(signInWithIdToken).not.toHaveBeenCalled();
  });
});
