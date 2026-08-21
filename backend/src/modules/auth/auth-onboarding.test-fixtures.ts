import assert from "node:assert/strict";
import type { ConsentVersionRow, UserConsentRow, UserRow } from "../../shared/types/database";
import type {
  CompleteOnboardingPayload,
  ConsentKey,
  OnboardingBodyMeasurementRow,
  OnboardingBodyMeasurementValues,
  OnboardingRepository,
  OnboardingUserProfile,
  SaveUserConsentInput
} from "./auth-onboarding.types";

process.env.SUPABASE_URL = process.env.SUPABASE_URL ?? "http://localhost:54321";
process.env.SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY ?? "anon-key";
process.env.SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "service-role-key";

export const fixedNow = new Date("2026-07-08T00:00:00.000Z");

export type CompleteOnboardingWithRepository =
  typeof import("./auth-onboarding.service").completeOnboardingWithRepository;

export type Operation =
  | { readonly kind: "user"; readonly profile: OnboardingUserProfile }
  | { readonly kind: "consent"; readonly key: ConsentKey; readonly accepted: boolean; readonly required: boolean }
  | { readonly kind: "body"; readonly action: "insert" | "update"; readonly id: string };

type FakeState = {
  readonly consentVersions?: readonly ConsentVersionRow[];
  readonly existingBodyMeasurements?: readonly OnboardingBodyMeasurementRow[];
};

export const consentVersion = (
  key: ConsentKey,
  required: boolean,
  version = "2026-07-07"
): ConsentVersionRow => ({
  key,
  version,
  title: key,
  description: null,
  required,
  effective_from: "2026-07-07T00:00:00.000Z",
  created_at: "2026-07-07T00:00:00.000Z"
});

const allConsentVersions = [
  consentVersion("terms_of_service", true),
  consentVersion("privacy_policy", true),
  consentVersion("fit_data_improvement", false),
  consentVersion("marketing", false)
] as const;

export const payload = (
  overrides: Partial<CompleteOnboardingPayload> = {}
): CompleteOnboardingPayload => ({
  displayName: "  Mina  ",
  consents: {
    terms_of_service: { accepted: true, version: "2026-07-07" },
    privacy_policy: { accepted: true, version: "2026-07-07" }
  },
  ...overrides
});

export const bodyRow = (
  id: string,
  values: Partial<OnboardingBodyMeasurementRow> = {}
): OnboardingBodyMeasurementRow => ({
  id,
  user_id: "user-1",
  height_cm: null,
  weight_kg: null,
  shoulder_width: null,
  chest_circumference: null,
  waist_circumference: null,
  hip_circumference: null,
  outseam: null,
  raw_data: { source: "onboarding" },
  created_at: fixedNow.toISOString(),
  updated_at: fixedNow.toISOString(),
  ...values
});

export const createFakeRepository = (state: FakeState = {}) => {
  const operations: Operation[] = [];
  const versions = state.consentVersions ?? allConsentVersions;
  const bodyRows = [...(state.existingBodyMeasurements ?? [])];
  const users: UserRow[] = [];
  const consents: UserConsentRow[] = [];
  const writtenBodies: OnboardingBodyMeasurementValues[] = [];

  const repository: OnboardingRepository = {
    findLatestConsentVersion: async (key) => {
      return versions.find((version) => version.key === key) ?? null;
    },
    upsertUserProfile: async (profile) => {
      operations.push({ kind: "user", profile });
      const row: UserRow = {
        id: profile.id,
        email: profile.email,
        display_name: profile.displayName,
        gender: profile.gender ?? null,
        birth_date: profile.birthDate ?? null,
        birth_year: profile.birthYear ?? null,
        created_at: fixedNow.toISOString(),
        updated_at: fixedNow.toISOString()
      };
      users.push(row);
      return row;
    },
    saveUserConsent: async (input: SaveUserConsentInput) => {
      operations.push({
        kind: "consent",
        key: input.consentKey,
        accepted: input.accepted,
        required: input.required
      });
      const row: UserConsentRow = {
        id: `consent-${consents.length + 1}`,
        user_id: input.userId,
        consent_key: input.consentKey,
        consent_version: input.consentVersion,
        accepted: input.accepted,
        accepted_at: input.accepted ? input.nowIso : null,
        revoked_at: null,
        required: input.required,
        ip_address: input.ipAddress,
        user_agent: input.userAgent,
        created_at: input.nowIso,
        updated_at: input.nowIso
      };
      consents.push(row);
      return row;
    },
    findLatestOnboardingBodyMeasurement: async () => {
      return bodyRows.find((row) => row.raw_data.source === "onboarding") ?? null;
    },
    insertOnboardingBodyMeasurement: async (userId, values) => {
      writtenBodies.push(values);
      const row = bodyRow(`body-${bodyRows.length + 1}`, {
        user_id: userId,
        height_cm: values.height_cm ?? null,
        weight_kg: values.weight_kg ?? null,
        raw_data: values.raw_data
      });
      operations.push({ kind: "body", action: "insert", id: row.id });
      bodyRows.push(row);
      return row;
    },
    updateOnboardingBodyMeasurement: async (id, values) => {
      writtenBodies.push(values);
      operations.push({ kind: "body", action: "update", id });
      return bodyRows.find((row) => row.id === id) ?? bodyRow(id);
    }
  };

  return { repository, operations, bodyRows, users, consents, writtenBodies };
};

export const assertRejectsWithStatus = async (
  action: () => Promise<unknown>,
  statusCode: number
): Promise<void> => {
  await assert.rejects(action, (error: unknown) => {
    assert.ok(error instanceof Error);
    assert.equal("statusCode" in error ? error.statusCode : undefined, statusCode);
    return true;
  });
};

export const loadCompleteOnboarding = async (): Promise<CompleteOnboardingWithRepository> => {
  const service = await import("./auth-onboarding.service");
  return service.completeOnboardingWithRepository;
};
