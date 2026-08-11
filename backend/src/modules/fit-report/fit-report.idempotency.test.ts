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

  const [{ supabase }, { generateFitReport }] = await Promise.all([
    import("../../config/supabase"),
    import("./fit-report.service")
  ]);
  Object.defineProperty(supabase, "from", {
    value: (table: string): FakeSupabaseQuery => new FakeSupabaseQuery(table)
  });
  Object.defineProperty(supabase, "rpc", {
    value: () => ({
      single: async () => ({
        data: { available_threads: 34, status: "already_consumed" },
        error: null
      })
    })
  });
  useEnrichedFitResult();

  let openRouterCalls = 0;
  globalThis.fetch = async (): Promise<Response> => {
    openRouterCalls += 1;
    throw new Error("OpenRouter must not run after an already-consumed report charge");
  };

  const result = await generateFitReport(userId, fitResultId, {
    idempotencyKey: "77777777-7777-4777-8777-777777777777"
  });

  assert.equal(openRouterCalls, 0);
  assert.equal(result.source, "fallback");
  assert.equal(result.availableThreads, 34);
};

main().then(
  () => console.log("PASS returns the deterministic report without another OpenRouter request"),
  (error: unknown) => {
    if (error instanceof Error) {
      console.error(error.message);
    } else {
      console.error("Unknown test failure");
    }
    process.exit(1);
  }
);
