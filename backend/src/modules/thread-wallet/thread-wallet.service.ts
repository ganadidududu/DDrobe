import { supabase } from "../../config/supabase";
import { createHttpError } from "../../shared/utils/http-error";
import type { PreparedFitRecommendation } from "../fit/fit.service";

interface ThreadBalanceRow {
  available_threads: number;
}

interface ThreadConsumptionRow extends ThreadBalanceRow {
  status: "already_consumed" | "consumed" | "insufficient";
}

interface ThreadLedgerRow {
  fit_analysis_result_id: string | null;
}

interface AtomicFitAnalysisRow extends ThreadBalanceRow {
  fit_analysis_result_id: string | null;
  status: "already_consumed" | "consumed" | "insufficient";
}

export const getThreadBalance = async (userId: string): Promise<number> => {
  const { data, error } = await supabase
    .rpc("get_thread_balance", { p_user_id: userId })
    .single<ThreadBalanceRow>();
  if (error || !data) throw createHttpError(500, "Failed to load thread balance");
  return data.available_threads;
};

export const consumeFitAnalysisThread = async (
  userId: string,
  idempotencyKey: string,
  fitAnalysisResultId: string
): Promise<number> => {
  const { data, error } = await supabase
    .rpc("consume_fit_analysis_thread", {
      p_user_id: userId,
      p_idempotency_key: idempotencyKey,
      p_fit_analysis_result_id: fitAnalysisResultId
    })
    .single<ThreadConsumptionRow>();
  if (error || !data) throw createHttpError(500, "Failed to consume thread");
  if (data.status === "already_consumed") {
    throw createHttpError(409, "이미 처리한 핏 분석 요청이에요. 히스토리에서 결과를 확인해 주세요.");
  }
  if (data.status === "insufficient") {
    throw createHttpError(402, "실타래가 부족해요. 충전 후 다시 시도해 주세요.");
  }
  return data.available_threads;
};

export const findFitAnalysisThreadConsumption = async (
  userId: string,
  idempotencyKey: string
): Promise<string | null> => {
  const { data, error } = await supabase
    .from("thread_ledger_entries")
    .select("fit_analysis_result_id")
    .eq("user_id", userId)
    .eq("idempotency_key", idempotencyKey)
    .limit(1)
    .returns<ThreadLedgerRow[]>();
  if (error) throw createHttpError(500, "Failed to check analysis request state");
  return data?.[0]?.fit_analysis_result_id ?? null;
};

export const createFitAnalysisAndConsumeThread = async (
  userId: string,
  idempotencyKey: string,
  prepared: PreparedFitRecommendation["persistence"]
): Promise<{
  status: AtomicFitAnalysisRow["status"];
  fitAnalysisResultId: string | null;
  availableThreads: number;
}> => {
  const { data, error } = await supabase
    .rpc("create_fit_analysis_result_and_consume_thread", {
      p_user_id: userId,
      p_idempotency_key: idempotencyKey,
      p_result: prepared
    })
    .single<AtomicFitAnalysisRow>();
  if (error || !data) throw createHttpError(500, "Failed to save fit analysis and consume thread");
  return {
    status: data.status,
    fitAnalysisResultId: data.fit_analysis_result_id,
    availableThreads: data.available_threads
  };
};
