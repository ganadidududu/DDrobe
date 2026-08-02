import assert from "node:assert/strict";
import {
  configureReportTestEnv,
  FakeSupabaseQuery,
  fitResultId,
  forbiddenTokens,
  useAdversarialConsumedMetadataFitResult,
  useConflictingFeedbackFitResult,
  useEnrichedFitResult,
  useInsufficientFeedbackFitResult,
  usePartialConfidenceBreakdownFitResult,
  useLegacyFitResult,
  userId
} from "./fit-report.service.test-fixtures";
import { assertSanitizerContract, countSentences } from "./fit-report.sanitizer.test-cases";

const main = async (): Promise<void> => {
  configureReportTestEnv();

  const [{ supabase }, reportBuilder, promptModule, reportService, reportSanitizer] = await Promise.all([
    import("../../config/supabase"),
    import("./fit-report.builder"),
    import("./fit-report.prompt"),
    import("./fit-report.service"),
    import("./fit-report.sanitizer")
  ]);

  Object.defineProperty(supabase, "from", {
    value: (table: string): FakeSupabaseQuery => new FakeSupabaseQuery(table)
  });

  useLegacyFitResult();
  const legacyReportInput = await reportBuilder.buildFitReportInput(userId, fitResultId);
  assert.equal(legacyReportInput.recommendation.recommendedSize, "S");
  assert.equal(legacyReportInput.recommendation.scoreGapToSecond, 3);
  assert.equal(legacyReportInput.sizeScores.length, 2);
  assert.equal(legacyReportInput.explanation.missingMeasurementSummary.summary, "unavailable");

  useEnrichedFitResult();
  const reportInput = await reportBuilder.buildFitReportInput(userId, fitResultId);
  assert.deepEqual(
    reportInput.explanation.missingMeasurementSummary.missingMeasurementKeys,
    ["total_length"]
  );
  assert.equal(reportInput.explanation.dataQualitySummary.summary, "sparse");
  assert.equal(reportInput.explanation.feedbackReliability.summary, "unavailable");
  assert.equal(reportInput.explanation.feedbackReliability.status, "unavailable");
  assert.equal(reportInput.explanation.feedbackReliability.weightedSampleCount, 0);
  assert.equal(reportInput.explanation.topExplanationFactors[0]?.label, "가슴단면");
  assert.ok(reportInput.explanation.confidenceReasons.some((reason) => reason.code === "missing_measurements"));

  const fallbackReport = reportService.buildFallbackFitReport(reportInput);
  assertSanitizerContract(reportInput, fallbackReport, reportSanitizer);

  const prompt = promptModule.buildFitReportPrompt(reportInput);
  const narrativeInputStart = prompt.indexOf('{\n  "locale"');
  assert.ok(narrativeInputStart >= 0);
  const narrativeInput: unknown = JSON.parse(prompt.slice(narrativeInputStart));
  assert.ok(typeof narrativeInput === "object" && narrativeInput !== null && !Array.isArray(narrativeInput));
  assert.equal("feedbackPersonalization" in narrativeInput, false);
  assert.equal("chartData" in narrativeInput, false);
  assert.equal("referenceClothingSummary" in narrativeInput, false);
  const narrativeRecommendation = Reflect.get(narrativeInput, "recommendation");
  assert.ok(
    typeof narrativeRecommendation === "object" &&
    narrativeRecommendation !== null &&
    !Array.isArray(narrativeRecommendation)
  );
  assert.equal("recommendationConfidence" in narrativeRecommendation, false);
  const narrativeGarmentContext = Reflect.get(narrativeInput, "garmentContext");
  assert.ok(
    typeof narrativeGarmentContext === "object" &&
    narrativeGarmentContext !== null &&
    !Array.isArray(narrativeGarmentContext)
  );
  assert.equal(Reflect.get(narrativeGarmentContext, "category"), reportInput.targetProduct.category);
  assert.equal(Reflect.get(narrativeGarmentContext, "fitType"), reportInput.targetProduct.fitType);
  const narrativeExplanation = Reflect.get(narrativeInput, "explanation");
  assert.ok(
    typeof narrativeExplanation === "object" &&
    narrativeExplanation !== null &&
    !Array.isArray(narrativeExplanation)
  );
  assert.equal("confidenceReasons" in narrativeExplanation, false);
  const narrativeFactors = Reflect.get(narrativeExplanation, "topExplanationFactors");
  assert.ok(Array.isArray(narrativeFactors));
  const firstNarrativeFactor: unknown = narrativeFactors[0];
  assert.ok(
    typeof firstNarrativeFactor === "object" &&
    firstNarrativeFactor !== null &&
    !Array.isArray(firstNarrativeFactor)
  );
  assert.equal("weightedImpact" in firstNarrativeFactor, false);
  for (const token of forbiddenTokens) {
    assert.equal(prompt.includes(token), false, `${token} leaked into prompt`);
  }

  const fallback = reportService.buildFallbackFitReport(reportInput);
  assert.ok(fallback.recommendationReason.length >= 120);
  assert.equal(fallback.measurementAnalysis.length, reportInput.measurements.length);
  assert.equal(JSON.stringify(fallback).includes("신뢰도"), false);
  assert.equal(JSON.stringify(fallback).includes("피드백"), false);

  const assertFeedbackNotApplied = async (
    status: "insufficient_signal" | "conflicting_feedback",
    expectedSampleCount: number
  ): Promise<void> => {
    const blockedReportInput = await reportBuilder.buildFitReportInput(userId, fitResultId);
    assert.equal(blockedReportInput.feedbackPersonalization.applied, false);
    assert.equal(blockedReportInput.feedbackPersonalization.sampleCount, expectedSampleCount);
    assert.equal(blockedReportInput.explanation.feedbackReliability.applied, false);
    assert.equal(blockedReportInput.explanation.feedbackReliability.status, status);

    const blockedFallback = reportService.buildFallbackFitReport(blockedReportInput);
    const serializedFallback = JSON.stringify(blockedFallback);
    assert.equal(serializedFallback.includes("피드백"), false);
    assert.equal(serializedFallback.includes("신뢰도"), false);
  };

  useInsufficientFeedbackFitResult();
  await assertFeedbackNotApplied("insufficient_signal", 1);

  useConflictingFeedbackFitResult();
  await assertFeedbackNotApplied("conflicting_feedback", 6);

  usePartialConfidenceBreakdownFitResult();
  const partialMetadataReportInput = await reportBuilder.buildFitReportInput(userId, fitResultId);
  assert.equal(partialMetadataReportInput.feedbackPersonalization.applied, false);
  const partialReliability = partialMetadataReportInput.explanation.feedbackReliability;
  assert.equal(partialMetadataReportInput.feedbackPersonalization.sampleCount, 9);
  assert.equal(partialReliability.applied, false);
  assert.equal(partialReliability.status, "insufficient_signal");
  assert.equal(partialReliability.weightedSampleCount, 9);

  useAdversarialConsumedMetadataFitResult();
  const adversarialReportInput = await reportBuilder.buildFitReportInput(userId, fitResultId);
  const adversarialPrompt = promptModule.buildFitReportPrompt(adversarialReportInput);
  const adversarialFallback = reportService.buildFallbackFitReport(adversarialReportInput);
  const adversarialArtifact = JSON.stringify({
    reportInput: adversarialReportInput,
    prompt: adversarialPrompt,
    fallback: adversarialFallback
  });
  for (const token of forbiddenTokens) {
    assert.equal(adversarialArtifact.includes(token), false, `${token} leaked through consumed metadata`);
  }
  assert.deepEqual(
    adversarialReportInput.explanation.confidenceReasons.map((reason) => reason.code),
    ["small_score_gap", "missing_measurements"]
  );
  assert.deepEqual(adversarialReportInput.explanation.topExplanationFactors, [
    {
      measurement: "chest_width",
      label: "가슴단면",
      diff: -3.2,
      weightedImpact: 1.28,
      status: "large_gap"
    }
  ]);
  assert.deepEqual(
    adversarialReportInput.explanation.missingMeasurementSummary.missingMeasurementKeys,
    ["total_length"]
  );
  assert.equal(adversarialReportInput.recommendation.weightingStrategy, null);
  assert.deepEqual(adversarialReportInput.feedbackPersonalization.partFeedbackCounts, {
    chest_width: { too_small: 2, good: 1 }
  });
  assert.deepEqual(adversarialReportInput.sizeScores, [
    {
      sizeLabel: "M",
      fitScore: 69,
      fitLabel: "good_fit",
      weightedFitDistance: 1.4,
      recommendationConfidence: "high"
    },
    {
      sizeLabel: "프리",
      fitScore: 62,
      fitLabel: "acceptable",
      weightedFitDistance: 2.2,
      recommendationConfidence: "medium"
    }
  ]);

  useEnrichedFitResult();
  let observedOpenRouterRequest: object | null = null;
  globalThis.fetch = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    assert.equal(String(input), "https://openrouter.ai/api/v1/chat/completions");
    assert.equal(typeof init?.body, "string");
    const requestBody: unknown = JSON.parse(typeof init?.body === "string" ? init.body : "");
    assert.ok(typeof requestBody === "object" && requestBody !== null && !Array.isArray(requestBody));
    observedOpenRouterRequest = requestBody;
    return new Response(JSON.stringify({
      choices: [{
        message: { content: JSON.stringify(fallback) }
      }]
    }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });
  };

  const generated = await reportService.generateFitReport(userId, fitResultId, { includeDebug: true });
  assert.equal(Reflect.get(observedOpenRouterRequest ?? {}, "model"), "google/gemini-2.5-flash");
  assert.equal(Reflect.get(observedOpenRouterRequest ?? {}, "stream"), false);
  const responseFormat = Reflect.get(observedOpenRouterRequest ?? {}, "response_format");
  assert.ok(typeof responseFormat === "object" && responseFormat !== null && !Array.isArray(responseFormat));
  assert.equal(Reflect.get(responseFormat, "type"), "json_schema");
  const provider = Reflect.get(observedOpenRouterRequest ?? {}, "provider");
  assert.ok(typeof provider === "object" && provider !== null && !Array.isArray(provider));
  assert.equal(Reflect.get(provider, "require_parameters"), true);
  assert.equal(Reflect.get(provider, "zdr"), true);
  assert.equal(Reflect.get(provider, "data_collection"), "deny");
  assert.equal(generated.source, "openrouter");
  assert.equal(generated.modelName, "google/gemini-2.5-flash");
  assert.equal(generated.promptVersion, "fit_report_v6");
  assert.equal(generated.report.summary.includes("S"), true);
  assert.equal(generated.report.summary.includes("67"), true);
  const generatedReliability = generated.reportInput?.explanation.feedbackReliability;
  assert.equal(generatedReliability?.status, "unavailable");
  assert.equal(generatedReliability?.weightedSampleCount, 0);
  assert.ok(countSentences(generated.report.summary) >= 4);
  assert.ok(countSentences(generated.report.recommendationReason) >= 6);
  assert.ok(generated.report.measurementAnalysis.every((row) => countSentences(row.text) >= 3));

  globalThis.fetch = async (): Promise<Response> =>
    new Response(JSON.stringify({
      choices: [{ message: { content: JSON.stringify({
        title: "정밀 핏 리포트",
        summary: "기준 의류가 한 벌뿐입니다.",
        recommendationReason: "피드백 데이터가 부재합니다.",
        measurementAnalysis: [{
          measurement: reportInput.measurements[0]?.label,
          text: "기준 999cm와 상품 888cm를 비교한 분석입니다."
        }],
        cautions: [],
        nextActions: []
      }) } }]
    }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });

  const sanitized = await reportService.generateFitReport(userId, fitResultId);
  assert.equal(sanitized.source, "fallback");
  assert.equal(sanitized.report.measurementAnalysis.length, reportInput.measurements.length);
  assert.equal(JSON.stringify(sanitized.report.measurementAnalysis).includes("999"), false);
  const firstMeasurement = sanitized.report.measurementAnalysis[0]?.text;
  assert.ok(firstMeasurement?.includes(`${reportInput.measurements[0]?.ideal}cm`));
  assert.ok(sanitized.report.summary.length >= 80);
  assert.ok(sanitized.report.recommendationReason.length >= 120);
  assert.ok(countSentences(sanitized.report.summary) >= 4);
  assert.ok(countSentences(sanitized.report.recommendationReason) >= 6);
  assert.ok(sanitized.report.measurementAnalysis.every((row) => countSentences(row.text) >= 3));
  assert.doesNotMatch(
    JSON.stringify(sanitized.report),
    /저신뢰도|신뢰도|피드백|한\s*벌뿐|판단\s*근거[^.!?\n]{0,20}제한/
  );

  console.log("fit-report tests passed");
};

main().catch((error: unknown) => {
  if (error instanceof Error) {
    console.error(error.message);
  }
  throw error;
});
