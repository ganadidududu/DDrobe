import { afterEach, describe, expect, it, vi } from "vitest";

const requiredEnvironment = {
  SUPABASE_URL: "https://supabase.example",
  SUPABASE_ANON_KEY: "test-anon-key",
  SUPABASE_SERVICE_ROLE_KEY: "test-service-role-key"
} as const;

const environmentKeys = [
  "NODE_ENV",
  "CORS_ORIGINS",
  "SUPABASE_URL",
  "SUPABASE_ANON_KEY",
  "SUPABASE_SERVICE_ROLE_KEY"
] as const;

const loadProductionEnv = async (corsOrigins: string) => {
  for (const [key, value] of Object.entries(requiredEnvironment)) {
    process.env[key] = value;
  }
  process.env.NODE_ENV = "production";
  process.env.CORS_ORIGINS = corsOrigins;
  vi.resetModules();
  return import("./env");
};

afterEach(() => {
  for (const key of environmentKeys) {
    delete process.env[key];
  }
});

describe("production CORS origins", () => {
  it("accepts exact HTTPS origins", async () => {
    // Given: production is configured with an exact HTTPS browser origin.
    // When: the environment module is loaded.
    const { env } = await loadProductionEnv("https://app.example");

    // Then: the HTTPS origin is available in the CORS allowlist.
    expect(env.corsOrigins).toEqual(["https://app.example"]);
  });

  it("rejects HTTP origins", async () => {
    // Given: production is configured with an HTTP browser origin.
    // When: the environment module is loaded.
    const load = loadProductionEnv("http://legacy.example");

    // Then: loading fails because production CORS origins must use HTTPS.
    await expect(load).rejects.toThrow(
      "CORS_ORIGINS contains an invalid origin: http://legacy.example"
    );
  });
});
