import assert from "node:assert/strict";
import type { FitReportInput, FitReportJson } from "./fit-report.types";

type SanitizeGeneratedReport = (
  report: FitReportJson,
  reportInput: FitReportInput,
  fallback: FitReportJson
) => FitReportJson;

type SanitizerApi = {
  readonly sanitizeGeneratedReport: SanitizeGeneratedReport;
  readonly hasAcceptedCoreNarrative: (
    report: FitReportJson,
    reportInput: FitReportInput
  ) => boolean;
};

export const countSentences = (text: string): number =>
  text.split(/[.!?。]+/).filter((sentence) => sentence.trim().length > 0).length;

export const assertSanitizerContract = (
  reportInput: FitReportInput,
  fallbackReport: FitReportJson,
  sanitizer: SanitizerApi
): void => {
  const { hasAcceptedCoreNarrative, sanitizeGeneratedReport } = sanitizer;
  const weightedDistanceSummary =
    `${fallbackReport.summary} 내부 가중 거리는 ${reportInput.recommendation.fitScore}입니다.`;
  const weightedDistanceSanitized = sanitizeGeneratedReport(
    { ...fallbackReport, summary: weightedDistanceSummary },
    reportInput,
    fallbackReport
  );
  assert.equal(weightedDistanceSanitized.summary, fallbackReport.summary);

  const misattributedMeasurementSummary =
    `${fallbackReport.summary} 가슴단면은 ${reportInput.recommendation.fitScore}cm 차이입니다.`;
  const misattributedMeasurementSanitized = sanitizeGeneratedReport(
    { ...fallbackReport, summary: misattributedMeasurementSummary },
    reportInput,
    fallbackReport
  );
  assert.equal(misattributedMeasurementSanitized.summary, fallbackReport.summary);

  const sampleScarcityPhrases = [
    "참조 의류가 충분하지 않아 판단 자료가 제한됩니다.",
    "기준으로 삼은 옷의 표본이 적습니다.",
    "기준 데이터가 부족해 분석 근거가 제한됩니다."
  ];
  for (const phrase of sampleScarcityPhrases) {
    const sampleScarcitySanitized = sanitizeGeneratedReport(
      { ...fallbackReport, summary: `${fallbackReport.summary} ${phrase}` },
      reportInput,
      fallbackReport
    );
    assert.equal(sampleScarcitySanitized.summary, fallbackReport.summary);
  }

  const unsignedDiffReport = {
    ...fallbackReport,
    measurementAnalysis: reportInput.measurements.map((row) => ({
      measurement: row.label,
      text: row.diff === 0
        ? fallbackReport.measurementAnalysis.find((item) => item.measurement === row.label)?.text ?? ""
        : `${row.label}은 기준 ${row.ideal}cm와 상품 ${row.product}cm를 비교하면 ` +
          `${row.diff < 0 ? "+" : ""}${Math.abs(row.diff)}cm 차이입니다. ` +
          "입력과 반대이거나 부호가 빠진 차이를 사용한 문장입니다. 구매 전 방향을 다시 확인해야 합니다."
    }))
  };
  const signedDiffSanitized = sanitizeGeneratedReport(
    unsignedDiffReport,
    reportInput,
    fallbackReport
  );
  for (const row of reportInput.measurements.filter((measurement) => measurement.diff !== 0)) {
    const expected = fallbackReport.measurementAnalysis.find((item) => item.measurement === row.label);
    assert.ok(expected);
    assert.equal(
      signedDiffSanitized.measurementAnalysis.find((item) => item.measurement === row.label)?.text,
      expected.text
    );
  }

  const boundedListsSanitized = sanitizeGeneratedReport(
    {
      ...fallbackReport,
      cautions: ["소재를 확인하세요.", "신축성을 확인하세요.", "두께를 확인하세요."],
      nextActions: ["상세표를 확인하세요.", "기준 옷과 비교하세요.", "레이어링을 확인하세요."]
    },
    reportInput,
    fallbackReport
  );
  assert.equal(boundedListsSanitized.cautions.length, 2);
  assert.equal(boundedListsSanitized.nextActions.length, 2);

  const partiallyUsableReport = {
    ...fallbackReport,
    summary:
      "추천 사이즈는 후보 중 전체적인 폭과 길이 균형이 가장 안정적입니다. " +
      "상품 실루엣은 기준으로 삼은 옷보다 일부 부위에서 여유롭게 나타납니다.",
    recommendationReason:
      "추천 후보는 폭과 길이를 함께 비교했을 때 가장 일관된 균형을 보였습니다. " +
      "다른 후보보다 한 부위의 장점에 치우치지 않아 최종 선택에 유리합니다."
  };
  assert.equal(hasAcceptedCoreNarrative(partiallyUsableReport, reportInput), true);
  const repairedNarrative = sanitizeGeneratedReport(
    partiallyUsableReport,
    reportInput,
    fallbackReport
  );
  assert.match(repairedNarrative.summary, /전체적인 폭과 길이 균형/);
  assert.match(repairedNarrative.recommendationReason, /가장 일관된 균형/);
  assert.ok(countSentences(repairedNarrative.summary) >= 4);
  assert.ok(countSentences(repairedNarrative.recommendationReason) >= 6);

  const rejectedCoreReport = {
    ...fallbackReport,
    summary: "기준 의류가 한 벌뿐입니다.",
    recommendationReason: "피드백 데이터가 부재합니다."
  };
  assert.equal(hasAcceptedCoreNarrative(rejectedCoreReport, reportInput), false);
};
