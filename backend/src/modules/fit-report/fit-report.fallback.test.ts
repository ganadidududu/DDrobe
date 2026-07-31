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
  const [{ supabase }, reportBuilder, fallbackModule] = await Promise.all([
    import("../../config/supabase"),
    import("./fit-report.builder"),
    import("./fit-report.fallback")
  ]);
  Object.defineProperty(supabase, "from", {
    value: (table: string): FakeSupabaseQuery => new FakeSupabaseQuery(table)
  });

  useEnrichedFitResult();
  const shirtReportInput = await reportBuilder.buildFitReportInput(userId, fitResultId);
  const pantsReportInput: typeof shirtReportInput = {
    ...shirtReportInput,
    targetProduct: {
      ...shirtReportInput.targetProduct,
      category: "pants"
    }
  };
  const shirtFallback = fallbackModule.buildFallbackFitReport(shirtReportInput);
  const pantsFallback = fallbackModule.buildFallbackFitReport(pantsReportInput);
  const shirtLastSentences = shirtFallback.measurementAnalysis.map((item) =>
    item.text.split(/[.!?。]+/).map((sentence) => sentence.trim()).filter(Boolean).at(-1) ?? ""
  );

  assert.notEqual(
    shirtFallback.measurementAnalysis.map((item) => item.text).join("\n"),
    pantsFallback.measurementAnalysis.map((item) => item.text).join("\n")
  );
  assert.equal(new Set(shirtLastSentences).size, shirtFallback.measurementAnalysis.length);
  assert.equal(
    shirtFallback.measurementAnalysis.find((item) => item.measurement === "어깨")?.text.startsWith("어깨는"),
    true
  );

  console.log("fit-report fallback tests passed");
};

main().catch((error: unknown) => {
  if (error instanceof Error) console.error(error.message);
  throw error;
});
