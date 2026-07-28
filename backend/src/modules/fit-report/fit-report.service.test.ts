import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
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
import {
  assertSanitizerContract,
  countSentences
} from "./fit-report.sanitizer.test-cases";

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
  assert.deepEqual(reportInput.explanation.missingMeasurementSummary.missingMeasurementKeys, ["total_length"]);
  assert.equal(reportInput.explanation.dataQualitySummary.summary, "sparse");
  assert.equal(reportInput.explanation.feedbackReliability.summary, "unavailable");
  assert.equal(reportInput.explanation.feedbackReliability.status, "unavailable");
  assert.equal(reportInput.explanation.feedbackReliability.weightedSampleCount, 0);
  assert.equal(reportInput.explanation.topExplanationFactors[0]?.label, "가슴단면");
  assert.ok(reportInput.explanation.confidenceReasons.some((reason) => reason.code === "missing_measurements"));

  const fallbackReport = reportService.buildFallbackFitReport(reportInput);
  assertSanitizerContract(
    reportInput,
    fallbackReport,
    reportSanitizer.sanitizeGeneratedReport
  );

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
  assert.ok(fallback.recommendationReason.includes("균형"));
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
  assert.equal(partialMetadataReportInput.feedbackPersonalization.sampleCount, 9);
  assert.equal(partialMetadataReportInput.explanation.feedbackReliability.applied, false);
  assert.equal(partialMetadataReportInput.explanation.feedbackReliability.status, "insufficient_signal");
  assert.equal(partialMetadataReportInput.explanation.feedbackReliability.weightedSampleCount, 9);

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
  assert.deepEqual(adversarialReportInput.explanation.missingMeasurementSummary.missingMeasurementKeys, [
    "total_length"
  ]);
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
  globalThis.fetch = async (): Promise<Response> =>
    new Response(JSON.stringify({ response: "not valid json" }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });

  const generated = await reportService.generateFitReport(userId, fitResultId, { includeDebug: true });
  assert.equal(generated.source, "fallback");
  assert.equal(generated.promptVersion, "fit_report_v5");
  assert.equal(generated.report.summary.includes("S"), true);
  assert.equal(generated.report.summary.includes("67"), true);
  assert.equal(generated.reportInput?.explanation.feedbackReliability.status, "unavailable");
  assert.equal(generated.reportInput?.explanation.feedbackReliability.weightedSampleCount, 0);
  assert.ok(countSentences(generated.report.summary) >= 4);
  assert.ok(countSentences(generated.report.recommendationReason) >= 6);
  assert.ok(generated.report.measurementAnalysis.every((row) => countSentences(row.text) >= 3));

  globalThis.fetch = async (): Promise<Response> =>
    new Response(JSON.stringify({
      response: JSON.stringify({
        title: "정밀 핏 리포트",
        summary: "추천 사이즈의 전체 균형을 확인했습니다. 폭과 길이를 나누어 비교했습니다. 기준 의류가 한 벌뿐이라 판단 근거가 제한됩니다. 구매 전에는 상품 상세 정보를 다시 확인하는 편이 좋습니다.",
        recommendationReason: "추천 후보의 점수를 비교했습니다. 폭 계열 차이를 확인했습니다. 길이 계열 차이도 확인했습니다. 피드백 데이터가 부재해 추천 근거는 약합니다. 가장 가까운 후보도 함께 살펴봤습니다. 최종 선택 전에는 소재를 확인하세요.",
        measurementAnalysis: [{
          measurement: reportInput.measurements[0]?.label,
          text: "기준 999cm와 상품 888cm를 비교한 분석입니다."
        }],
        cautions: [],
        nextActions: []
      })
    }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });

  const sanitized = await reportService.generateFitReport(userId, fitResultId);
  assert.equal(sanitized.source, "fallback");
  assert.equal(sanitized.report.measurementAnalysis.length, reportInput.measurements.length);
  assert.equal(JSON.stringify(sanitized.report.measurementAnalysis).includes("999"), false);
  assert.ok(sanitized.report.measurementAnalysis[0]?.text.includes(`${reportInput.measurements[0]?.ideal}cm`));
  assert.ok(sanitized.report.summary.length >= 80);
  assert.ok(sanitized.report.recommendationReason.length >= 120);
  assert.ok(countSentences(sanitized.report.summary) >= 4);
  assert.ok(countSentences(sanitized.report.recommendationReason) >= 6);
  assert.ok(sanitized.report.measurementAnalysis.every((row) => countSentences(row.text) >= 3));
  assert.doesNotMatch(
    JSON.stringify(sanitized.report),
    /저신뢰도|신뢰도|피드백|한\s*벌뿐|판단\s*근거[^.!?\n]{0,20}제한/
  );

  const snapshotPath = resolve(tmpdir(), "coordit-fit-report-tests", "fit-report.json");
  await mkdir(dirname(snapshotPath), { recursive: true });
  await writeFile(snapshotPath, `${JSON.stringify({
    source: generated.source,
    recommendedSize: generated.reportInput?.recommendation.recommendedSize,
    fitScore: generated.reportInput?.recommendation.fitScore,
    explanation: generated.reportInput?.explanation,
    fallbackReport: generated.report
  }, null, 2)}\n`);

  const promptSafetyPath = resolve(tmpdir(), "coordit-fit-report-tests", "prompt-safety.log");
  await writeFile(
    promptSafetyPath,
    `prompt safety passed\nforbidden raw/private token checks: ${forbiddenTokens.length}\nprompt length: ${prompt.length}\n`
  );

  console.log("fit-report tests passed");
};

main().catch((error: unknown) => {
  if (error instanceof Error) {
    console.error(error.message);
  }
  throw error;
});
