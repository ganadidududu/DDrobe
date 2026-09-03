import { describe, expect, it, vi } from "vitest";
import { refreshAuthSession } from "./auth-refresh.service";

describe("refreshAuthSession", () => {
  it("returns the rotated Supabase token pair", async () => {
    const refreshSession = vi.fn().mockResolvedValue({
      data: {
        session: {
          access_token: "new-access-token",
          refresh_token: "new-refresh-token",
        },
      },
      error: null,
    });

    await expect(refreshAuthSession("old-refresh-token", { refreshSession })).resolves.toEqual({
      accessToken: "new-access-token",
      refreshToken: "new-refresh-token",
    });
    expect(refreshSession).toHaveBeenCalledWith({ refresh_token: "old-refresh-token" });
  });

  it("maps rejected refresh credentials to HTTP 401", async () => {
    const refreshSession = vi.fn().mockResolvedValue({
      data: { session: null },
      error: { message: "Invalid Refresh Token", status: 400 },
    });

    await expect(refreshAuthSession("expired-refresh-token", { refreshSession })).rejects.toMatchObject({
      statusCode: 401,
    });
  });

  it("maps transient Supabase failures to HTTP 503", async () => {
    const refreshSession = vi.fn().mockResolvedValue({
      data: { session: null },
      error: { message: "upstream unavailable", status: 503 },
    });

    await expect(refreshAuthSession("valid-refresh-token", { refreshSession })).rejects.toMatchObject({
      statusCode: 503,
    });
  });
});
