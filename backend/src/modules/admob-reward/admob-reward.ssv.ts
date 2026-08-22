import { createVerify } from "node:crypto";
import { z } from "zod";

const callbackParameterOrder = [
  "ad_network",
  "ad_unit",
  "custom_data",
  "reward_amount",
  "reward_item",
  "timestamp",
  "transaction_id",
  "user_id"
] as const;

const base64URLSchema = z.string().min(1).regex(/^[A-Za-z0-9_-]+$/u);
const keyIdSchema = z.string().regex(/^\d+$/u).transform(Number).pipe(
  z.number().int().safe().nonnegative()
);
const decimalSchema = z.string().regex(/^\d+$/u).transform(Number).pipe(
  z.number().int().safe().nonnegative()
);
const callbackSchema = z.object({
  ad_network: z.string().regex(/^\d+$/u),
  ad_unit: z.string().min(1),
  custom_data: z.string().min(1),
  reward_amount: decimalSchema,
  reward_item: z.string().min(1),
  timestamp: decimalSchema,
  transaction_id: z.string().min(1).max(128).regex(/^[0-9a-f]+$/iu),
  user_id: z.string().min(1).optional()
}).strict();
const attemptIdSchema = z.string().uuid();

export type VerifierKey = {
  readonly keyId: number;
  readonly pem: string;
};

export type AdMobSSVConfiguration = {
  readonly rewardedAdsEnabled: boolean;
  readonly adUnitId: string;
  readonly rewardItem: string;
  readonly rewardAmount: number;
  readonly validationCustomData: string;
};

export const admobSSVRejectionCategories = [
  "malformed-callback",
  "invalid-parameter-order",
  "unknown-key",
  "key-fetch-unavailable",
  "invalid-signature",
  "missing-custom-data",
  "invalid-custom-data",
  "unexpected-reward-config",
  "stale-timestamp",
  "rewards-disabled"
] as const;

export type AdMobSSVRejectionCategory = (typeof admobSSVRejectionCategories)[number];

export class AdMobSSVError extends Error {
  readonly name = "AdMobSSVError";

  constructor(
    readonly category: AdMobSSVRejectionCategory,
    readonly statusCode: number,
    options?: ErrorOptions
  ) {
    super(
      statusCode === 503
        ? "AdMob rewarded verification is temporarily unavailable"
        : "Invalid AdMob rewarded callback",
      options
    );
  }
}

type VerificationDependencies = {
  readonly getVerifierKeys: () => Promise<readonly VerifierKey[]>;
  readonly now: () => number;
  readonly configuration: AdMobSSVConfiguration;
};

type SignatureVerificationInput = {
  readonly signedContent: string;
  readonly rawSignature: string;
  readonly rawKeyId: string;
};

export type VerifiedAdMobCallback =
  | { readonly kind: "validation" }
  | {
    readonly kind: "reward";
    readonly attemptId: string;
    readonly transactionId: string;
  };

const rejectCallback = (
  category: AdMobSSVRejectionCategory,
  statusCode = 400,
  cause?: unknown
): never => {
  throw new AdMobSSVError(category, statusCode, cause === undefined ? undefined : { cause });
};

const decodeValue = (rawValue: string): string => {
  try {
    return decodeURIComponent(rawValue);
  } catch (error) {
    if (error instanceof URIError) {
      return rejectCallback("malformed-callback", 400, error);
    }
    throw error;
  }
};

const decodeSignedContentForVerification = (rawSignedContent: string): string => {
  try {
    // AdMob signs Java URI.getQuery() bytes: percent escapes decode, literal '+' does not.
    return decodeURIComponent(rawSignedContent);
  } catch (error) {
    if (error instanceof URIError) {
      return rejectCallback("malformed-callback", 400, error);
    }
    throw error;
  }
};

const parseSignedContent = (signedContent: string): z.infer<typeof callbackSchema> => {
  const rawSegments = signedContent.split("&");
  const rawEntries = rawSegments.map((segment) => {
    const equalsIndex = segment.indexOf("=");
    if (equalsIndex <= 0) return rejectCallback("malformed-callback");
    return {
      name: segment.slice(0, equalsIndex),
      value: segment.slice(equalsIndex + 1)
    };
  });
  const names = rawEntries.map(({ name }) => name);
  const expectedNames = callbackParameterOrder.filter((name) => {
    return (name !== "user_id" && name !== "custom_data") || names.includes(name);
  });
  if (
    names.length !== expectedNames.length
    || names.some((name, index) => name !== expectedNames[index])
  ) {
    return rejectCallback("invalid-parameter-order");
  }

  // Mutable only while parsing this one untrusted boundary into a Zod-owned value.
  const decodedValues: Record<string, string> = {};
  for (const entry of rawEntries) {
    decodedValues[entry.name] = decodeValue(entry.value);
  }
  if (!("custom_data" in decodedValues)) {
    return rejectCallback("missing-custom-data");
  }
  const parsed = callbackSchema.safeParse(decodedValues);
  if (!parsed.success) return rejectCallback("malformed-callback");
  return parsed.data;
};

const verifySignature = async (
  input: SignatureVerificationInput,
  getVerifierKeys: () => Promise<readonly VerifierKey[]>
): Promise<void> => {
  const signatureResult = base64URLSchema.safeParse(input.rawSignature);
  const keyIdResult = keyIdSchema.safeParse(input.rawKeyId);
  if (!signatureResult.success || !keyIdResult.success) {
    return rejectCallback("malformed-callback");
  }
  let keys: readonly VerifierKey[];
  try {
    keys = await getVerifierKeys();
  } catch (error) {
    if (error instanceof Error) {
      return rejectCallback("key-fetch-unavailable", 503, error);
    }
    throw error;
  }
  const publicKey = keys.find(({ keyId }) => keyId === keyIdResult.data)?.pem;
  if (publicKey === undefined) return rejectCallback("unknown-key");

  try {
    const verifier = createVerify("SHA256");
    verifier.update(input.signedContent, "utf8");
    verifier.end();
    if (!verifier.verify(publicKey, Buffer.from(signatureResult.data, "base64url"))) {
      return rejectCallback("invalid-signature");
    }
  } catch (error) {
    if (error instanceof Error) {
      return rejectCallback("invalid-signature", 400, error);
    }
    throw error;
  }
};

export const verifyAdMobSSVCallback = async (
  originalURL: string,
  dependencies: VerificationDependencies
): Promise<VerifiedAdMobCallback> => {
  const queryIndex = originalURL.indexOf("?");
  if (queryIndex < 0) return rejectCallback("malformed-callback");
  const rawQuery = originalURL.slice(queryIndex + 1);
  const signatureMarker = "&signature=";
  const signatureIndex = rawQuery.lastIndexOf(signatureMarker);
  if (signatureIndex <= 0) return rejectCallback("malformed-callback");
  const signedContent = rawQuery.slice(0, signatureIndex);
  const signatureTail = rawQuery.slice(signatureIndex);
  const tailMatch = /^&signature=([^&]+)&key_id=([^&]+)$/u.exec(signatureTail);
  if (tailMatch === null) return rejectCallback("malformed-callback");
  const rawSignature = tailMatch[1];
  const rawKeyId = tailMatch[2];
  if (rawSignature === undefined || rawKeyId === undefined) {
    return rejectCallback("malformed-callback");
  }

  await verifySignature({
    signedContent: decodeSignedContentForVerification(signedContent),
    rawSignature,
    rawKeyId
  }, dependencies.getVerifierKeys);
  const callback = parseSignedContent(signedContent);
  const config = dependencies.configuration;
  if (Math.abs(dependencies.now() - callback.timestamp) > 86_400_000) {
    return rejectCallback("stale-timestamp");
  }
  if (callback.custom_data === config.validationCustomData) {
    return { kind: "validation" };
  }
  if (
    callback.ad_unit !== config.adUnitId
    || callback.reward_item !== config.rewardItem
    || callback.reward_amount !== config.rewardAmount
  ) {
    return rejectCallback("unexpected-reward-config");
  }
  const attemptResult = attemptIdSchema.safeParse(callback.custom_data);
  if (!attemptResult.success) return rejectCallback("invalid-custom-data");
  if (!config.rewardedAdsEnabled) return rejectCallback("rewards-disabled", 503);
  return {
    kind: "reward",
    attemptId: attemptResult.data,
    transactionId: callback.transaction_id
  };
};
