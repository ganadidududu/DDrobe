import assert from "node:assert/strict";
import {
  configureReportTestEnv,
  FakeSupabaseQuery,
  fitResultId,
  useEnrichedFitResult,
  userId
} from "./fit-report.service.test-fixtures";

const main = async (): Promise<void> => {
  configureReportTestEnv();

  const [{ supabase }, { buildFitReportInput }, reportService] = await Promise.all([
    import("../../config/supabase"),
    import("./fit-report.builder"),
    import("./fit-report.service")
  ]);
  Object.defineProperty(supabase, "from", {
    value: (table: string): FakeSupabaseQuery => new FakeSupabaseQuery(table)
  });
  let reportThreadRequests = 0;
  let balanceRequests = 0;
  let debits = 0;
  Object.defineProperty(supabase, "rpc", {
    value: (functionName: string, params: Record<string, string>) => ({
      single: async () => {
        assert.equal(params.p_user_id, userId);
        if (functionName === "get_thread_balance") {
          balanceRequests += 1;
          return { data: { available_threads: 34 }, error: null };
        }

        assert.equal(functionName, "consume_fit_report_thread");
        assert.equal(params.p_fit_analysis_result_id, fitResultId);
        assert.equal(params.p_idempotency_key, "77777777-7777-4777-8777-777777777777");
        reportThreadRequests += 1;
        if (reportThreadRequests === 1) debits += 1;
        return {
          data: {
            available_threads: 34,
            status: reportThreadRequests === 1 ? "consumed" : "already_consumed"
          },
          error: null
        };
      }
    })
  });

  // Given: a first report request and its retry share one idempotency key.
  useEnrichedFitResult();
  const reportInput = await buildFitReportInput(userId, fitResultId);
  const generatedCandidate = reportService.buildFallbackFitReport(reportInput);

  let openRouterCalls = 0;
  globalThis.fetch = async (): Promise<Response> => {
    openRouterCalls += 1;
    return new Response(JSON.stringify({
      choices: [{ message: { content: JSON.stringify(generatedCandidate) } }]
    }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });
  };

  // When: the client retries after the first report completes.
  const first = await reportService.generateFitReport(userId, fitResultId, {
    idempotencyKey: "77777777-7777-4777-8777-777777777777"
  });
  const retry = await reportService.generateFitReport(userId, fitResultId, {
    idempotencyKey: "77777777-7777-4777-8777-777777777777"
  });

  // Then: one debit and model generation produce one durable response reused by the retry.
  assert.equal(debits, 1);
  assert.equal(openRouterCalls, 1);
  assert.equal(reportThreadRequests, 1);
  assert.equal(balanceRequests, 1);
  assert.deepEqual(retry, first);
};

main().then(
  () => console.log("PASS reuses the persisted report without another debit or model generation"),
  (error: unknown) => {
    if (error instanceof Error) {
      console.error(error.message);
    } else {
      console.error("Unknown test failure");
    }
    process.exit(1);
  }
);
