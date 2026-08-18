import { supabase } from "../../config/supabase";
import type { ConsentVersionRow, UserConsentRow, UserRow } from "../../shared/types/database";
import { createHttpError } from "../../shared/utils/http-error";
import type {
  ConsentKey,
  OnboardingBodyMeasurementRow,
  OnboardingBodyMeasurementValues,
  OnboardingRepository,
  OnboardingUserProfile,
  SaveUserConsentInput
} from "./auth-onboarding.types";

type UserProfileUpsertRow = {
  id: string;
  email: string;
  display_name: string;
  gender?: string;
  birth_date?: string;
  birth_year?: number;
  updated_at: string;
};

type BodyMeasurementWriteRow = {
  user_id?: string;
  height_cm?: number | null;
  weight_kg?: number | null;
  raw_data: Record<string, unknown>;
  updated_at: string;
};

const toProfileRow = (profile: OnboardingUserProfile): UserProfileUpsertRow => {
  const row: UserProfileUpsertRow = {
    id: profile.id,
    email: profile.email,
    display_name: profile.displayName,
    updated_at: new Date().toISOString()
  };
  if (profile.gender !== undefined) row.gender = profile.gender;
  if (profile.birthDate !== undefined) row.birth_date = profile.birthDate;
  if (profile.birthYear !== undefined) row.birth_year = profile.birthYear;
  return row;
};

const toBodyMeasurementRow = (
  values: OnboardingBodyMeasurementValues,
  userId?: string
): BodyMeasurementWriteRow => {
  const row: BodyMeasurementWriteRow = {
    raw_data: values.raw_data,
    updated_at: new Date().toISOString()
  };
  if (userId !== undefined) row.user_id = userId;
  if (values.height_cm !== undefined) row.height_cm = values.height_cm;
  if (values.weight_kg !== undefined) row.weight_kg = values.weight_kg;
  return row;
};

export const supabaseOnboardingRepository: OnboardingRepository = {
  async findLatestConsentVersion(
    key: ConsentKey,
    nowIso: string
  ): Promise<ConsentVersionRow | null> {
    const { data, error } = await supabase
      .from("consent_versions")
      .select("*")
      .eq("key", key)
      .lte("effective_from", nowIso)
      .order("effective_from", { ascending: false })
      .order("version", { ascending: false })
      .limit(1)
      .maybeSingle<ConsentVersionRow>();

    if (error) throw createHttpError(500, "Failed to load consent versions");
    return data ?? null;
  },

  async upsertUserProfile(profile: OnboardingUserProfile): Promise<UserRow> {
    const { data, error } = await supabase
      .from("users")
      .upsert(toProfileRow(profile), { onConflict: "id" })
      .select("*")
      .single<UserRow>();

    if (error || !data) throw createHttpError(500, "Failed to save user profile");
    return data;
  },

  async saveUserConsent(input: SaveUserConsentInput): Promise<UserConsentRow> {
    const { data, error } = await supabase
      .from("user_consents")
      .upsert(
        {
          user_id: input.userId,
          consent_key: input.consentKey,
          consent_version: input.consentVersion,
          accepted: input.accepted,
          accepted_at: input.accepted ? input.nowIso : null,
          revoked_at: null,
          required: input.required,
          ip_address: input.ipAddress ?? null,
          user_agent: input.userAgent ?? null,
          updated_at: input.nowIso
        },
        { onConflict: "user_id,consent_key,consent_version" }
      )
      .select("*")
      .single<UserConsentRow>();

    if (error || !data) throw createHttpError(500, "Failed to save user consent");
    return data;
  },

  async findLatestOnboardingBodyMeasurement(
    userId: string
  ): Promise<OnboardingBodyMeasurementRow | null> {
    const { data, error } = await supabase
      .from("body_measurements")
      .select("*")
      .eq("user_id", userId)
      .filter("raw_data->>source", "eq", "onboarding")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle<OnboardingBodyMeasurementRow>();

    if (error) throw createHttpError(500, "Failed to load body measurements");
    return data ?? null;
  },

  async insertOnboardingBodyMeasurement(
    userId: string,
    values: OnboardingBodyMeasurementValues
  ): Promise<OnboardingBodyMeasurementRow> {
    const { data, error } = await supabase
      .from("body_measurements")
      .insert(toBodyMeasurementRow(values, userId))
      .select("*")
      .single<OnboardingBodyMeasurementRow>();

    if (error || !data) throw createHttpError(500, "Failed to save body measurement");
    return data;
  },

  async updateOnboardingBodyMeasurement(
    id: string,
    values: OnboardingBodyMeasurementValues
  ): Promise<OnboardingBodyMeasurementRow> {
    const { data, error } = await supabase
      .from("body_measurements")
      .update(toBodyMeasurementRow(values))
      .eq("id", id)
      .select("*")
      .single<OnboardingBodyMeasurementRow>();

    if (error || !data) throw createHttpError(500, "Failed to save body measurement");
    return data;
  }
};
