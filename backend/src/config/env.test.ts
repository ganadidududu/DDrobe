import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const requiredEnvironment = {
  SUPABASE_URL: "https://supabase.example",
  SUPABASE_ANON_KEY: "test-anon-key",
  SUPABASE_SERVICE_ROLE_KEY: "test-service-role-key"
} as const;

const appleRootCaG3DerBase64 = "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

const environmentKeys = [
  "NODE_ENV",
  "CORS_ORIGINS",
  "APPLE_IAP_ENABLED",
  "APPLE_IAP_BUNDLE_ID",
  "APPLE_IAP_APPLE_ID",
  "APPLE_IAP_ROOT_CERTIFICATE_PATHS",
  "ADMOB_REWARDED_ENABLED",
  "ADMOB_SSV_VALIDATION_CUSTOM_DATA",
  "ADMOB_REWARDED_AD_UNIT_ID",
  "ADMOB_REWARD_ITEM",
  "ADMOB_REWARD_AMOUNT",
  "SUPABASE_URL",
  "SUPABASE_ANON_KEY",
  "SUPABASE_SERVICE_ROLE_KEY"
] as const;

// Mutable only to guarantee cleanup when a test assertion or module import fails.
let temporaryCertificateDirectory: string | null = null;

const createCertificateFixture = async (contents: string | Uint8Array): Promise<string> => {
  temporaryCertificateDirectory = await mkdtemp(join(tmpdir(), "coordit-apple-root-"));
  const certificatePath = join(temporaryCertificateDirectory, "root-ca.der");
  await writeFile(certificatePath, contents);
  return certificatePath;
};

const loadProductionEnv = async (corsOrigins: string) => {
  for (const [key, value] of Object.entries(requiredEnvironment)) {
    process.env[key] = value;
  }
  process.env.NODE_ENV = "production";
  process.env.CORS_ORIGINS = corsOrigins;
  vi.resetModules();
  return import("./env");
};

beforeEach(() => {
  for (const key of environmentKeys) {
    delete process.env[key];
  }
  vi.resetModules();
});

afterEach(async () => {
  for (const key of environmentKeys) {
    delete process.env[key];
  }
  vi.resetModules();
  if (temporaryCertificateDirectory !== null) {
    const directory = temporaryCertificateDirectory;
    temporaryCertificateDirectory = null;
    await rm(directory, { recursive: true, force: true });
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

  it("reads the optional AdMob reward configuration", async () => {
    // Given: a release environment with a configured rewarded-ad unit.
    process.env.ADMOB_REWARDED_AD_UNIT_ID = "ca-app-pub-1234567890123456/1234567890";
    process.env.ADMOB_REWARD_ITEM = "thread";
    process.env.ADMOB_REWARD_AMOUNT = "2";

    // When: the environment module is loaded.
    const { env } = await loadProductionEnv("https://app.example");

    // Then: the verified SSV callback can compare the exact configured reward.
    expect(env.admobRewardedAdUnitId).toBe("ca-app-pub-1234567890123456/1234567890");
    expect(env.admobRewardItem).toBe("thread");
    expect(env.admobRewardAmount).toBe(2);
  });

  it("provides the non-secret AdMob SSV validation marker without enabling rewards", async () => {
    // Given: no AdMob feature flag or marker override is configured.
    // When: the environment module is loaded.
    const { env } = await loadProductionEnv("https://app.example");

    // Then: Todo 2 receives the stable validation marker while rewards remain disabled.
    expect(env.admobSsvValidationCustomData).toBe("coordit-admob-ssv-validation-v1");
    expect(env.admobRewardedEnabled).toBe(false);
  });

  it("keeps rewarded ads disabled when the feature flag is absent", async () => {
    // Given: no rewarded-ad feature flag is configured.
    // When: the environment module is loaded.
    const { env } = await loadProductionEnv("https://app.example");

    // Then: the release readiness flag fails closed.
    expect(env.admobRewardedEnabled).toBe(false);
  });

  it("keeps rewarded ads disabled when the feature flag is explicitly false", async () => {
    // Given: the rewarded-ad feature flag is explicitly disabled.
    process.env.ADMOB_REWARDED_ENABLED = "false";

    // When: the environment module is loaded.
    const { env } = await loadProductionEnv("https://app.example");

    // Then: rewarded ads remain unavailable.
    expect(env.admobRewardedEnabled).toBe(false);
  });

  it("enables rewarded ads only when the feature flag is exactly true", async () => {
    // Given: the rewarded-ad feature flag is explicitly enabled.
    process.env.ADMOB_REWARDED_ENABLED = "true";

    // When: the environment module is loaded.
    const { env } = await loadProductionEnv("https://app.example");

    // Then: rewarded ads are reported ready.
    expect(env.admobRewardedEnabled).toBe(true);
  });

  it("keeps rewarded ads disabled for a malformed feature flag", async () => {
    // Given: the rewarded-ad flag does not use the accepted literal value.
    process.env.ADMOB_REWARDED_ENABLED = "TRUE";

    // When: the environment module is loaded.
    const { env } = await loadProductionEnv("https://app.example");

    // Then: malformed configuration fails closed.
    expect(env.admobRewardedEnabled).toBe(false);
  });

  it("keeps Apple IAP settlement disabled by default", async () => {
    const { env } = await loadProductionEnv("https://app.example");

    expect(env.appleIapEnabled).toBe(false);
  });

  it("keeps Apple IAP disabled when explicitly false with complete verifier configuration", async () => {
    // Given: Apple verifier settings exist but the feature flag is explicitly disabled.
    process.env.APPLE_IAP_ENABLED = "false";
    process.env.APPLE_IAP_APPLE_ID = "123456789";
    process.env.APPLE_IAP_ROOT_CERTIFICATE_PATHS = "/secrets/apple-root-ca.pem";

    // When: the environment module is loaded.
    const { env } = await loadProductionEnv("https://app.example");

    // Then: IAP remains unavailable.
    expect(env.appleIapEnabled).toBe(false);
  });

  it("keeps Apple IAP disabled when enabled without mandatory verifier configuration", async () => {
    // Given: the Apple feature flag is true but the app ID and root certificate paths are absent.
    process.env.APPLE_IAP_ENABLED = "true";

    // When: the environment module is loaded.
    const { env } = await loadProductionEnv("https://app.example");

    // Then: the dangerous partial configuration fails closed.
    expect(env.appleIapEnabled).toBe(false);
  });

  it("keeps Apple IAP disabled when the verifier app ID is malformed", async () => {
    // Given: Apple IAP is requested with a root certificate path but an invalid app ID.
    process.env.APPLE_IAP_ENABLED = "true";
    process.env.APPLE_IAP_APPLE_ID = "not-a-positive-integer";
    process.env.APPLE_IAP_ROOT_CERTIFICATE_PATHS = "/secrets/apple-root-ca.pem";

    // When: the environment module is loaded.
    const { env } = await loadProductionEnv("https://app.example");

    // Then: malformed verifier configuration fails closed.
    expect(env.appleIapEnabled).toBe(false);
  });

  it("keeps Apple IAP disabled when the root certificate path is not a regular file", async () => {
    // Given: Apple IAP is requested with a positive app ID but a readable device path.
    process.env.APPLE_IAP_ENABLED = "true";
    process.env.APPLE_IAP_APPLE_ID = "123456789";
    process.env.APPLE_IAP_ROOT_CERTIFICATE_PATHS = "/dev/null";

    // When: the environment module is loaded.
    const { env } = await loadProductionEnv("https://app.example");

    // Then: a non-file root path cannot make IAP ready.
    expect(env.appleIapEnabled).toBe(false);
  });

  it("keeps Apple IAP disabled when the root certificate path does not exist", async () => {
    // Given: Apple IAP is requested with a positive app ID but a missing root certificate.
    process.env.APPLE_IAP_ENABLED = "true";
    process.env.APPLE_IAP_APPLE_ID = "123456789";
    process.env.APPLE_IAP_ROOT_CERTIFICATE_PATHS =
      `/tmp/coordit-missing-apple-root-${process.pid}.pem`;

    // When: the environment module is loaded.
    const { env } = await loadProductionEnv("https://app.example");

    // Then: the missing path cannot make IAP ready.
    expect(env.appleIapEnabled).toBe(false);
  });

  it("keeps Apple IAP disabled when the root certificate file is empty", async () => {
    // Given: Apple IAP is requested with an empty readable regular-file root fixture.
    const certificatePath = await createCertificateFixture(new Uint8Array());
    process.env.APPLE_IAP_ENABLED = "true";
    process.env.APPLE_IAP_APPLE_ID = "123456789";
    process.env.APPLE_IAP_ROOT_CERTIFICATE_PATHS = certificatePath;

    // When: the environment module performs the verifier preflight.
    const { env } = await loadProductionEnv("https://app.example");

    // Then: a certificate the Apple verifier cannot parse fails closed.
    expect(env.appleIapEnabled).toBe(false);
  });

  it("keeps Apple IAP disabled when the root certificate file is malformed", async () => {
    // Given: Apple IAP is requested with malformed X.509 bytes in a readable file.
    const certificatePath = await createCertificateFixture("not-a-der-certificate");
    process.env.APPLE_IAP_ENABLED = "true";
    process.env.APPLE_IAP_APPLE_ID = "123456789";
    process.env.APPLE_IAP_ROOT_CERTIFICATE_PATHS = certificatePath;

    // When: the environment module performs the verifier preflight.
    const { env } = await loadProductionEnv("https://app.example");

    // Then: a certificate the Apple verifier cannot construct fails closed.
    expect(env.appleIapEnabled).toBe(false);
  });

  it("enables Apple IAP only when the installed verifier accepts the root certificate", async () => {
    // Given: a real Apple Root CA G3 DER fixture and the mandatory verifier settings.
    const certificatePath = await createCertificateFixture(
      Buffer.from(appleRootCaG3DerBase64, "base64")
    );
    process.env.APPLE_IAP_ENABLED = "true";
    process.env.APPLE_IAP_APPLE_ID = "123456789";
    process.env.APPLE_IAP_ROOT_CERTIFICATE_PATHS = certificatePath;

    // When: the environment module is loaded.
    const { env } = await loadProductionEnv("https://app.example");

    // Then: Apple IAP is reported ready.
    expect(env.appleIapEnabled).toBe(true);
  });
});
