import assert from "node:assert/strict";
import type { OnboardingStatusRepository } from "./auth-onboarding-status.service";

process.env.SUPABASE_URL = process.env.SUPABASE_URL ?? "http://localhost:54321";
process.env.SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY ?? "anon-key";
process.env.SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "service-role-key";

const consentVersions = [
  { key: "terms_of_service", version: "2026-07-07" },
  { key: "privacy_policy", version: "2026-07-07" }
] as const;

const createRepository = (overrides: Partial<OnboardingStatusRepository> = {}): OnboardingStatusRepository => ({
  findUserProfile: async () => ({ display_name: "Mina" }),
  findLatestRequiredConsentVersions: async () => consentVersions,
  findUserConsents: async () => [
    { consent_key: "terms_of_service", consent_version: "2026-07-07", accepted: true, revoked_at: null },
    { consent_key: "privacy_policy", consent_version: "2026-07-07", accepted: true, revoked_at: null }
  ],
  ...overrides
});

const loadStatusCheck = async (): Promise<typeof import("./auth-onboarding-status.service").isOnboardingCompleteWithRepository> => {
  const module = await import("./auth-onboarding-status.service");
  return module.isOnboardingCompleteWithRepository;
};

const run = async (): Promise<void> => {
  const isOnboardingComplete = await loadStatusCheck();
  assert.equal(await isOnboardingComplete(createRepository(), "user-1"), true);
  assert.equal(
    await isOnboardingComplete(createRepository({ findUserProfile: async () => ({ display_name: null }) }), "user-1"),
    false
  );
  assert.equal(
    await isOnboardingComplete(createRepository({ findUserConsents: async () => [] }), "user-1"),
    false
  );
  await assert.rejects(
    () => isOnboardingComplete(createRepository({ findLatestRequiredConsentVersions: async () => [consentVersions[0]] }), "user-1"),
    (error: unknown) => error instanceof Error && "statusCode" in error && error.statusCode === 500
  );
  console.log("auth onboarding status tests passed");
};

run().catch((error: unknown) => {
  if (error instanceof Error) {
    console.error(error);
    process.exit(1);
  }
  console.error("Unknown test failure");
  process.exit(1);
});
