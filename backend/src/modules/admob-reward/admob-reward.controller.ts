import { createVerify } from "crypto";
import type { NextFunction, Request, Response } from "express";
import { env } from "../../config/env";
import type { AuthenticatedRequest } from "../../shared/types/http";
import { createHttpError } from "../../shared/utils/http-error";
import { requireUser } from "../../shared/utils/request";
import { createRewardAttempt, getRewardAttempt, grantRewardForVerifiedCallback } from "./admob-reward.service";

interface VerifierKey { keyId: number; pem: string; }
let cachedKeys: VerifierKey[] = [];
let keysExpireAt = 0;
const verifierKeysURL = "https://gstatic.com/admob/reward/verifier-keys.json";

const verifierKeys = async (): Promise<VerifierKey[]> => {
  if (cachedKeys.length && Date.now() < keysExpireAt) return cachedKeys;
  const response = await fetch(verifierKeysURL);
  if (!response.ok) throw createHttpError(503, "AdMob verifier keys are unavailable");
  const body = await response.json() as { keys?: VerifierKey[] };
  if (!Array.isArray(body.keys) || !body.keys.length) throw createHttpError(503, "AdMob verifier keys are invalid");
  cachedKeys = body.keys;
  keysExpireAt = Date.now() + 24 * 60 * 60 * 1000;
  return cachedKeys;
};

const required = (value: string | undefined, name: string): string => {
  if (!value) throw createHttpError(400, `Missing AdMob callback parameter: ${name}`);
  return value;
};

const verifyGoogleCallback = async (req: Request) => {
  const rawQuery = req.originalUrl.split("?", 2)[1] ?? "";
  const signatureIndex = rawQuery.lastIndexOf("&signature=");
  if (signatureIndex < 0) throw createHttpError(400, "Missing AdMob callback signature");
  // Verify Google's untouched UTF-8 query substring. Never reorder or re-encode it.
  const signedQuery = rawQuery.slice(0, signatureIndex);
  const params = new URLSearchParams(rawQuery);
  const signature = required(params.get("signature") ?? undefined, "signature");
  const keyId = Number(required(params.get("key_id") ?? undefined, "key_id"));
  const publicKey = (await verifierKeys()).find((key) => key.keyId === keyId)?.pem;
  if (!publicKey) throw createHttpError(400, "Unknown AdMob verifier key");
  const verifier = createVerify("SHA256");
  verifier.update(signedQuery, "utf8");
  verifier.end();
  if (!verifier.verify(publicKey, Buffer.from(signature, "base64url"))) throw createHttpError(400, "Invalid AdMob callback signature");
  const adUnit = required(params.get("ad_unit") ?? undefined, "ad_unit");
  const rewardItem = required(params.get("reward_item") ?? undefined, "reward_item");
  const rewardAmount = Number(required(params.get("reward_amount") ?? undefined, "reward_amount"));
  const timestamp = Number(required(params.get("timestamp") ?? undefined, "timestamp"));
  if (adUnit !== env.admobRewardedAdUnitId || rewardItem !== env.admobRewardItem || rewardAmount !== env.admobRewardAmount) throw createHttpError(400, "Unexpected AdMob reward configuration");
  if (!Number.isFinite(timestamp) || Math.abs(Date.now() - timestamp) > 24 * 60 * 60 * 1000) throw createHttpError(400, "Stale AdMob callback timestamp");
  return { attemptId: required(params.get("custom_data") ?? undefined, "custom_data"), transactionId: required(params.get("transaction_id") ?? undefined, "transaction_id") };
};

export const createRewardAttemptController = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try { res.status(201).json(await createRewardAttempt(requireUser(req).id)); } catch (error) { next(error); }
};
export const getRewardAttemptController = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try { res.json(await getRewardAttempt(requireUser(req).id, req.params.id)); } catch (error) { next(error); }
};
// Google authenticates this public route with its SSV signature.
export const receiveRewardedSSVController = async (req: Request, res: Response, next: NextFunction) => {
  try { const callback = await verifyGoogleCallback(req); res.status(200).json(await grantRewardForVerifiedCallback(callback.attemptId, callback.transactionId)); } catch (error) { next(error); }
};
