import type { ConsentVersionRow, UserConsentRow, UserRow } from "../../shared/types/database";

export const REQUIRED_CONSENT_KEYS = ["terms_of_service", "privacy_policy"] as const;
export const OPTIONAL_CONSENT_KEYS = ["fit_data_improvement", "marketing"] as const;

export type RequiredConsentKey = (typeof REQUIRED_CONSENT_KEYS)[number];
export type OptionalConsentKey = (typeof OPTIONAL_CONSENT_KEYS)[number];
export type ConsentKey = RequiredConsentKey | OptionalConsentKey;

export type OnboardingAuthUser = {
  readonly id: string;
  readonly email?: string | null;
};

export type OnboardingConsentPayload = {
  readonly accepted?: unknown;
  readonly version?: unknown;
};

export type CompleteOnboardingPayload = {
  readonly displayName?: unknown;
  readonly display_name?: unknown;
  readonly gender?: unknown;
  readonly birthDate?: unknown;
  readonly birth_date?: unknown;
  readonly bodyMeasurements?: unknown;
  readonly body_measurements?: unknown;
  readonly consents?: unknown;
};

export type CompleteOnboardingOptions = {
  readonly now?: Date;
  readonly ipAddress?: string | null;
  readonly userAgent?: string | null;
};

export type OnboardingUserProfile = {
  readonly id: string;
  readonly email: string;
  readonly displayName: string;
  readonly gender?: string;
  readonly birthDate?: string;
  readonly birthYear?: number;
};

export type OnboardingBodyMeasurementValues = {
  readonly height_cm?: number | null;
  readonly weight_kg?: number | null;
  readonly raw_data: Record<string, unknown>;
};

export type OnboardingBodyMeasurementRow = {
  readonly id: string;
  readonly user_id: string;
  readonly height_cm: number | null;
  readonly weight_kg: number | null;
  readonly shoulder_width: number | null;
  readonly chest_circumference: number | null;
  readonly waist_circumference: number | null;
  readonly hip_circumference: number | null;
  readonly outseam: number | null;
  readonly raw_data: Record<string, unknown>;
  readonly created_at: string;
  readonly updated_at: string;
};

export type SaveUserConsentInput = {
  readonly userId: string;
  readonly consentKey: ConsentKey;
  readonly consentVersion: string;
  readonly accepted: boolean;
  readonly required: boolean;
  readonly nowIso: string;
  readonly ipAddress: string | null;
  readonly userAgent: string | null;
};

export type OnboardingRepository = {
  readonly findLatestConsentVersion: (
    key: ConsentKey,
    nowIso: string
  ) => Promise<ConsentVersionRow | null>;
  readonly upsertUserProfile: (profile: OnboardingUserProfile) => Promise<UserRow>;
  readonly saveUserConsent: (input: SaveUserConsentInput) => Promise<UserConsentRow>;
  readonly findLatestOnboardingBodyMeasurement: (
    userId: string
  ) => Promise<OnboardingBodyMeasurementRow | null>;
  readonly insertOnboardingBodyMeasurement: (
    userId: string,
    values: OnboardingBodyMeasurementValues
  ) => Promise<OnboardingBodyMeasurementRow>;
  readonly updateOnboardingBodyMeasurement: (
    id: string,
    values: OnboardingBodyMeasurementValues
  ) => Promise<OnboardingBodyMeasurementRow>;
};

export type CompleteOnboardingResult = {
  readonly user: UserRow;
  readonly onboardingComplete: true;
  readonly bodyMeasurementsSaved: boolean;
  readonly consentRows: readonly UserConsentRow[];
};
