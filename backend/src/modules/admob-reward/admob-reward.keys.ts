import { z } from "zod";
import type { VerifierKey } from "./admob-reward.ssv";

const googleVerifierKeysURL = "https://gstatic.com/admob/reward/verifier-keys.json";
const maximumCacheMs = 86_400_000;
const keyResponseSchema = z.object({
  keys: z.array(z.object({
    keyId: z.number().int().safe().nonnegative(),
    pem: z.string().min(1)
  })).min(1)
}).passthrough();

export class AdMobVerifierKeyDownloadError extends Error {
  readonly name = "AdMobVerifierKeyDownloadError";

  constructor(readonly reason: "http" | "payload", options?: ErrorOptions) {
    super("AdMob verifier key download failed", options);
  }
}

export type VerifierKeyProvider = () => Promise<readonly VerifierKey[]>;

export const createCachedVerifierKeyProvider = (
  download: () => Promise<unknown>,
  now: () => number
): VerifierKeyProvider => {
  // Mutable cache state is the purpose of this provider closure.
  let cachedKeys: readonly VerifierKey[] = [];
  let expiresAt = 0;

  return async () => {
    const requestTime = now();
    if (cachedKeys.length > 0 && requestTime < expiresAt) return cachedKeys;
    const payload = await download();
    const parsed = keyResponseSchema.safeParse(payload);
    if (!parsed.success) throw new AdMobVerifierKeyDownloadError("payload");
    cachedKeys = parsed.data.keys;
    expiresAt = now() + maximumCacheMs;
    return cachedKeys;
  };
};

const downloadGoogleVerifierKeys = async (): Promise<unknown> => {
  let response: Response;
  try {
    response = await fetch(googleVerifierKeysURL, {
      signal: AbortSignal.timeout(5_000)
    });
  } catch (error) {
    throw new AdMobVerifierKeyDownloadError("http", { cause: error });
  }
  if (!response.ok) throw new AdMobVerifierKeyDownloadError("http");
  return response.json();
};

export const getGoogleVerifierKeys = createCachedVerifierKeyProvider(
  downloadGoogleVerifierKeys,
  Date.now
);
