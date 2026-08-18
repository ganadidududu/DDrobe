import { supabase } from "../../config/supabase";
import { createHttpError } from "../../shared/utils/http-error";
import { REQUIRED_CONSENT_KEYS, type RequiredConsentKey } from "./auth-onboarding.types";

type UserProfileStatus = {
  readonly display_name: string | null;
};

type RequiredConsentVersion = {
  readonly key: RequiredConsentKey;
  readonly version: string;
};

type UserConsent = {
  readonly consent_key: RequiredConsentKey;
  readonly consent_version: string;
  readonly accepted: boolean;
  readonly revoked_at: string | null;
};

export type OnboardingStatusRepository = {
  readonly findUserProfile: (userId: string) => Promise<UserProfileStatus | null>;
  readonly findLatestRequiredConsentVersions: (nowIso: string) => Promise<readonly RequiredConsentVersion[]>;
  readonly findUserConsents: (userId: string) => Promise<readonly UserConsent[]>;
};

const latestVersionsByKey = (versions: readonly RequiredConsentVersion[]): Map<RequiredConsentKey, string> => {
  const latestVersions = new Map<RequiredConsentKey, string>();
  for (const version of versions) {
    if (!latestVersions.has(version.key)) latestVersions.set(version.key, version.version);
  }
  return latestVersions;
};

export const isOnboardingCompleteWithRepository = async (
  repository: OnboardingStatusRepository,
  userId: string,
  now = new Date()
): Promise<boolean> => {
  const [profile, versions] = await Promise.all([
    repository.findUserProfile(userId),
    repository.findLatestRequiredConsentVersions(now.toISOString())
  ]);

  if (!profile?.display_name) return false;

  const latestVersions = latestVersionsByKey(versions);
  if (latestVersions.size !== REQUIRED_CONSENT_KEYS.length) {
    throw createHttpError(500, "Required consent versions are missing");
  }

  const consents = await repository.findUserConsents(userId);
  return REQUIRED_CONSENT_KEYS.every((key) => {
    const requiredVersion = latestVersions.get(key);
    return consents.some((consent) => {
      return consent.consent_key === key
        && consent.consent_version === requiredVersion
        && consent.accepted
        && consent.revoked_at === null;
    });
  });
};

const supabaseOnboardingStatusRepository: OnboardingStatusRepository = {
  async findUserProfile(userId: string): Promise<UserProfileStatus | null> {
    const { data, error } = await supabase
      .from("users")
      .select("display_name")
      .eq("id", userId)
      .maybeSingle<UserProfileStatus>();
    if (error) throw createHttpError(500, "Failed to check onboarding status");
    return data ?? null;
  },

  async findLatestRequiredConsentVersions(nowIso: string): Promise<readonly RequiredConsentVersion[]> {
    const { data, error } = await supabase
      .from("consent_versions")
      .select("key, version")
      .in("key", REQUIRED_CONSENT_KEYS)
      .lte("effective_from", nowIso)
      .order("effective_from", { ascending: false })
      .order("version", { ascending: false });
    if (error) throw createHttpError(500, "Failed to check onboarding status");
    return data ?? [];
  },

  async findUserConsents(userId: string): Promise<readonly UserConsent[]> {
    const { data, error } = await supabase
      .from("user_consents")
      .select("consent_key, consent_version, accepted, revoked_at")
      .eq("user_id", userId)
      .in("consent_key", REQUIRED_CONSENT_KEYS);
    if (error) throw createHttpError(500, "Failed to check user consent status");
    return data ?? [];
  }
};

export const isOnboardingCompleteForUser = async (userId: string): Promise<boolean> => {
  return isOnboardingCompleteWithRepository(supabaseOnboardingStatusRepository, userId);
};
