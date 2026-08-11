import { supabase } from "../../config/supabase";
import { createHttpError } from "../../shared/utils/http-error";

interface RewardAttemptRow {
  id: string;
  status: "pending" | "granted" | "expired";
  expires_at: string;
}

interface GrantRow {
  available_threads: number;
  status: "granted" | "already_granted" | "expired" | "unknown_attempt";
}

export const createRewardAttempt = async (userId: string) => {
  const { data, error } = await supabase
    .rpc("create_admob_reward_attempt", { p_user_id: userId })
    .single<RewardAttemptRow>();
  if (error || !data) throw createHttpError(500, "Failed to create reward attempt");
  return { attemptId: data.id, expiresAt: data.expires_at, status: data.status };
};

export const getRewardAttempt = async (userId: string, attemptId: string) => {
  const { data, error } = await supabase
    .from("admob_reward_attempts")
    .select("id, status, expires_at")
    .eq("id", attemptId)
    .eq("user_id", userId)
    .maybeSingle<RewardAttemptRow>();
  if (error) throw createHttpError(500, "Failed to load reward attempt");
  if (!data) throw createHttpError(404, "Reward attempt not found");
  return { attemptId: data.id, expiresAt: data.expires_at, status: data.status };
};

export const grantRewardForVerifiedCallback = async (attemptId: string, transactionId: string) => {
  const { data, error } = await supabase
    .rpc("grant_admob_reward", { p_attempt_id: attemptId, p_transaction_id: transactionId })
    .single<GrantRow>();
  if (error || !data) throw createHttpError(500, "Failed to grant verified AdMob reward");
  if (data.status === "unknown_attempt") throw createHttpError(404, "Unknown reward attempt");
  if (data.status === "expired") throw createHttpError(409, "Expired reward attempt");
  return { status: data.status, availableThreads: data.available_threads };
};
