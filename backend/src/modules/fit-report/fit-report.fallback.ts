import {
  buildEverydayFitLens,
  buildFitTradeoffLens,
  buildGarmentNarrativeContext,
  buildMaterialAndLayeringCaution
} from "./fit-report.garment-context";
import { buildMeasurementAnalysisText } from "./fit-report.sanitizer";
import type { FitReportInput, FitReportJson } from "./fit-report.types";

const formatTopExplanationFactors = (reportInput: FitReportInput): string => {
  const factors = reportInput.explanation.topExplanationFactors.map((factor) => factor.label);
  return factors.length > 0 ? factors.join(", ") : "부위별 균형";
};

const formatCandidateScores = (reportInput: FitReportInput): string => reportInput.sizeScores
  .filter((size) => size.sizeLabel !== reportInput.recommendation.recommendedSize)
  .map((size) => `${size.sizeLabel} ${size.fitScore}점`)
  .join(", ");

export const buildFallbackFitReport = (reportInput: FitReportInput): FitReportJson => {
  const garmentContext = buildGarmentNarrativeContext(reportInput.targetProduct);
  const topExplanationFactors = formatTopExplanationFactors(reportInput);
  const competingSizes = formatCandidateScores(reportInput);
  const recommendationGap = reportInput.recommendation.scoreGapToSecond === null
    ? ""
    : ` 가장 가까운 후보와의 점수 차이는 ${reportInput.recommendation.scoreGapToSecond}점입니다.`;

  return {
    title: `${reportInput.recommendation.recommendedSize} 사이즈 ${garmentContext.categoryLabel} 핏 분석`,
    summary:
      `${reportInput.recommendation.recommendedSize} 사이즈는 핏 스코어 ${reportInput.recommendation.fitScore}점으로 이 ${garmentContext.categoryLabel}에서 가장 균형적인 후보입니다. ` +
      `${garmentContext.fitTypeLabel}을 기준으로 보면, 한 부위만 완전히 맞추기보다 폭과 길이에서 생기는 타협점을 고르게 관리한 선택입니다. ` +
      `${topExplanationFactors} 차이가 전체 점수에 가장 크게 반영되어 추천 사이즈의 실루엣을 결정했습니다. ` +
      `${buildEverydayFitLens(reportInput.targetProduct)}`,
    recommendationReason:
      `${reportInput.recommendation.recommendedSize} 사이즈가 추천된 이유는 모든 후보 가운데 기준 의류와 가장 가까운 조합을 만들었기 때문입니다.` +
      (competingSizes.length > 0 ? ` 다른 후보의 점수는 ${competingSizes}입니다.` : "") +
      recommendationGap +
      ` 특히 ${topExplanationFactors} 차이는 ${garmentContext.categoryLabel}의 ${garmentContext.bodyArea} 실루엣에서 눈에 띕니다. ` +
      `${garmentContext.fitTypeLabel}의 의도와 비교해 폭이 남는 부위는 여유 있는 연출로, 길이가 달라지는 부위는 평소 비율의 변화로 해석했습니다. ` +
      `${buildFitTradeoffLens(reportInput.targetProduct)} ` +
      "따라서 아래 부위별 설명에서 본인이 허용할 수 있는 여유와 길이 변화를 확인한 뒤 이 사이즈를 고르는 것을 권합니다.",
    measurementAnalysis: reportInput.measurements.map((row) => ({
      measurement: row.label,
      text: buildMeasurementAnalysisText(row, reportInput.targetProduct)
    })),
    cautions: [buildMaterialAndLayeringCaution(reportInput.targetProduct)],
    nextActions: [
      "상품 상세 착용 사진에서 차이가 큰 부위가 몸의 어느 위치에 오는지 기준 의류와 나란히 확인하세요.",
      "구매 전 평소 단독 착용인지 이너·아우터와 함께 입을지 정한 뒤 해당 상황의 여유를 다시 확인하세요."
    ]
  };
};
