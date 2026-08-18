import { createHttpError } from "../../shared/utils/http-error";
import type { ConsentVersionRow } from "../../shared/types/database";
import { asOptionalNumber, asOptionalRecord, asOptionalString } from "../../shared/utils/request";
import {
  OPTIONAL_CONSENT_KEYS,
  REQUIRED_CONSENT_KEYS,
  type CompleteOnboardingPayload,
  type ConsentKey,
  type OnboardingBodyMeasurementValues,
  type OnboardingConsentPayload,
  type OnboardingRepository,
  type OptionalConsentKey,
  type RequiredConsentKey
} from "./auth-onboarding.types";

export type ParsedConsent = {
  readonly key: ConsentKey;
  readonly accepted: boolean;
  readonly version: string;
  readonly required: boolean;
};

export type ParsedOnboardingInput = {
  readonly displayName: string;
  readonly gender?: string;
  readonly birthDate?: string;
  readonly birthYear?: number;
  readonly bodyMeasurements: OnboardingBodyMeasurementValues | null;
  readonly consents: readonly ParsedConsent[];
};

const BODY_MEASUREMENT_FIELDS = [
  ["height_cm", "heightCm", "height_cm"],
  ["weight_kg", "weightKg", "weight_kg"]
] as const;

const ALLOWED_GENDERS = ["female", "male", "prefer_not_to_say"] as const;

const isConsentKey = (key: string): key is ConsentKey => {
  switch (key) {
    case "terms_of_service":
    case "privacy_policy":
    case "fit_data_improvement":
    case "marketing":
      return true;
    default:
      return false;
  }
};

const readConsentPayload = (
  consents: Record<string, unknown>,
  key: ConsentKey
): OnboardingConsentPayload | null => {
  const value = consents[key];
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value;
};

const readConsentVersion = (payload: OnboardingConsentPayload, key: ConsentKey): string => {
  const version = asOptionalString(payload.version);
  if (!version) throw createHttpError(400, `${key} consent version is required`);
  return version;
};

const readAccepted = (payload: OnboardingConsentPayload, key: ConsentKey): boolean => {
  if (typeof payload.accepted !== "boolean") {
    throw createHttpError(400, `${key} consent accepted is required`);
  }
  return payload.accepted;
};

const pickNumber = (source: Record<string, unknown>, camelKey: string, snakeKey: string) => {
  return asOptionalNumber(source[camelKey] ?? source[snakeKey]);
};

const parseBodyMeasurements = (value: unknown): OnboardingBodyMeasurementValues | null => {
  const body = asOptionalRecord(value);
  const rawData = asOptionalRecord(body.rawData ?? body.raw_data);
  const parsed: Record<string, number | null> = {};
  let hasNumericValue = false;

  for (const [targetKey, camelKey, snakeKey] of BODY_MEASUREMENT_FIELDS) {
    const parsedValue = pickNumber(body, camelKey, snakeKey);
    if (parsedValue !== null) {
      parsed[targetKey] = parsedValue;
      hasNumericValue = true;
    }
  }

  if (!hasNumericValue) return null;

  return {
    height_cm: parsed.height_cm,
    weight_kg: parsed.weight_kg,
    raw_data: { ...rawData, source: "onboarding" }
  };
};

const parseBirthDate = (payload: CompleteOnboardingPayload): string | undefined => {
  const date = asOptionalString(payload.birthDate ?? payload.birth_date);
  if (!date) return undefined;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw createHttpError(400, "birthDate must use YYYY-MM-DD");
  }
  const parsed = new Date(`${date}T00:00:00.000Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== date) {
    throw createHttpError(400, "birthDate must be a real calendar date");
  }
  return date;
};

const parseGender = (payload: CompleteOnboardingPayload): string | undefined => {
  const gender = asOptionalString(payload.gender);
  if (!gender) return undefined;
  if (!ALLOWED_GENDERS.some((allowedGender) => allowedGender === gender)) {
    throw createHttpError(400, "gender is not supported");
  }
  return gender;
};

const parseRequiredConsent = (
  consents: Record<string, unknown>,
  key: RequiredConsentKey,
  latest: ConsentVersionRow
): ParsedConsent => {
  const payload = readConsentPayload(consents, key);
  if (!payload) throw createHttpError(400, `${key} consent is required`);
  const accepted = readAccepted(payload, key);
  if (!accepted) throw createHttpError(400, `${key} consent must be accepted`);
  const version = readConsentVersion(payload, key);
  if (version !== latest.version) {
    throw createHttpError(400, `${key} consent version must match the latest version`);
  }
  return { key, accepted, version, required: latest.required };
};

const parseOptionalConsent = (
  consents: Record<string, unknown>,
  key: OptionalConsentKey,
  latest: ConsentVersionRow
): ParsedConsent | null => {
  const payload = readConsentPayload(consents, key);
  if (!payload) return null;
  const accepted = readAccepted(payload, key);
  const version = readConsentVersion(payload, key);
  if (version !== latest.version) {
    throw createHttpError(400, `${key} consent version must match the latest version`);
  }
  return { key, accepted, version, required: latest.required };
};

const loadLatestConsentVersion = async (
  repository: OnboardingRepository,
  key: ConsentKey,
  nowIso: string
) => {
  const latest = await repository.findLatestConsentVersion(key, nowIso);
  if (!latest) throw createHttpError(500, `Latest consent version is missing for ${key}`);
  return latest;
};

export const parseOnboardingInput = async (
  repository: OnboardingRepository,
  payload: CompleteOnboardingPayload,
  nowIso: string
): Promise<ParsedOnboardingInput> => {
  const displayName = asOptionalString(payload.displayName ?? payload.display_name);
  if (!displayName) throw createHttpError(400, "displayName is required");

  const consents = asOptionalRecord(payload.consents);
  const parsedConsents: ParsedConsent[] = [];

  for (const key of REQUIRED_CONSENT_KEYS) {
    const latest = await loadLatestConsentVersion(repository, key, nowIso);
    parsedConsents.push(parseRequiredConsent(consents, key, latest));
  }

  for (const key of OPTIONAL_CONSENT_KEYS) {
    const payloadForKey = readConsentPayload(consents, key);
    if (!payloadForKey) continue;
    const latest = await loadLatestConsentVersion(repository, key, nowIso);
    const parsed = parseOptionalConsent(consents, key, latest);
    if (parsed) parsedConsents.push(parsed);
  }

  for (const key of Object.keys(consents)) {
    if (!isConsentKey(key)) throw createHttpError(400, `${key} is not a supported consent key`);
  }

  const birthDate = parseBirthDate(payload);

  return {
    displayName,
    gender: parseGender(payload),
    birthDate,
    birthYear: birthDate ? Number(birthDate.slice(0, 4)) : undefined,
    bodyMeasurements: parseBodyMeasurements(payload.bodyMeasurements ?? payload.body_measurements),
    consents: parsedConsents
  };
};
