import assert from "node:assert/strict";
import type { FitReportInput, FitReportJson } from "./fit-report.types";

type SanitizeGeneratedReport = (
  report: FitReportJson,
  reportInput: FitReportInput,
  fallback: FitReportJson
) => FitReportJson;

export const countSentences = (text: string): number =>
  text.split(/[.!?。]+/).filter((sentence) => sentence.trim().length > 0).length;

export const assertSanitizerContract = (
  reportInput: FitReportInput,
  fallbackReport: FitReportJson,
  sanitizeGeneratedReport: SanitizeGeneratedReport
): void => {
  const weightedDistanceSummary =
    `${fallbackReport.summary} 내부 계산 거리는 ${reportInput.recommendation.weightedFitDistance}입니다.`;
  const weightedDistanceSanitized = sanitizeGeneratedReport(
    { ...fallbackReport, summary: weightedDistanceSummary },
    reportInput,
    fallbackReport
  );
  assert.equal(weightedDistanceSanitized.summary, fallbackReport.summary);

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
};
