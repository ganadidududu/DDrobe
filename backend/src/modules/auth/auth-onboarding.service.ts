import { createHttpError } from "../../shared/utils/http-error";
import { parseOnboardingInput, type ParsedConsent } from "./auth-onboarding.parser";
import type {
  CompleteOnboardingOptions,
  CompleteOnboardingPayload,
  CompleteOnboardingResult,
  OnboardingAuthUser,
  OnboardingBodyMeasurementValues,
  OnboardingRepository,
  SaveUserConsentInput
} from "./auth-onboarding.types";

const saveBodyMeasurements = async (
  repository: OnboardingRepository,
  userId: string,
  values: OnboardingBodyMeasurementValues | null
): Promise<boolean> => {
  if (!values) return false;
  const existing = await repository.findLatestOnboardingBodyMeasurement(userId);
  if (existing) {
    await repository.updateOnboardingBodyMeasurement(existing.id, values);
    return true;
  }
  await repository.insertOnboardingBodyMeasurement(userId, values);
  return true;
};

const toConsentInput = (
  userId: string,
  consent: ParsedConsent,
  options: CompleteOnboardingOptions,
  nowIso: string
): SaveUserConsentInput => {
  return {
    userId,
    consentKey: consent.key,
    consentVersion: consent.version,
    accepted: consent.accepted,
    required: consent.required,
    nowIso,
    ipAddress: options.ipAddress ?? null,
    userAgent: options.userAgent ?? null
  };
};

export const completeOnboardingWithRepository = async (
  repository: OnboardingRepository,
  authUser: OnboardingAuthUser,
  payload: CompleteOnboardingPayload,
  options: CompleteOnboardingOptions = {}
): Promise<CompleteOnboardingResult> => {
  if (!authUser.email) throw createHttpError(400, "Auth user email is missing");

  const nowIso = (options.now ?? new Date()).toISOString();
  const parsed = await parseOnboardingInput(repository, payload, nowIso);
  const user = await repository.upsertUserProfile({
    id: authUser.id,
    email: authUser.email,
    displayName: parsed.displayName,
    gender: parsed.gender,
    birthDate: parsed.birthDate,
    birthYear: parsed.birthYear
  });

  const consentRows = [];
  for (const consent of parsed.consents) {
    consentRows.push(await repository.saveUserConsent(toConsentInput(user.id, consent, options, nowIso)));
  }

  const bodyMeasurementsSaved = await saveBodyMeasurements(
    repository,
    user.id,
    parsed.bodyMeasurements
  );

  return {
    user,
    onboardingComplete: true,
    bodyMeasurementsSaved,
    consentRows
  };
};

export const completeOnboarding = async (
  authUser: OnboardingAuthUser,
  payload: CompleteOnboardingPayload,
  options: CompleteOnboardingOptions = {}
): Promise<CompleteOnboardingResult> => {
  const { supabaseOnboardingRepository } = await import("./auth-onboarding.repository");
  return completeOnboardingWithRepository(supabaseOnboardingRepository, authUser, payload, options);
};
