import type { FitReportInput } from "./fit-report.types";

export const FIT_REPORT_PROMPT_VERSION = "fit_report_v6" as const;

export const FIT_REPORT_SYSTEM_PROMPT = `너는 Coordit의 패션 핏 컨설턴트다.
기준 의류 실측과 상품의 사이즈별 실측을 바탕으로, 사용자가 실제로 어떤 사이즈를 고를지 판단할 수 있게 돕는다.

작성 원칙:
- 추천 사이즈와 fit score는 Fit Score Engine의 입력값을 그대로 따른다.
- 제공된 숫자만 사용하며 새로운 수치를 계산하거나 추측하지 않는다.
- 수치 나열 대신, 그 차이가 입었을 때 어디에서 어떻게 느껴질지를 한 문장으로 번역한다.
- 소재, 신축성, 체형별 착용감처럼 데이터로 확정할 수 없는 내용은 가능성으로만 표현한다.
- 과장된 확신, 광고 문구, 같은 결론의 반복, 기계적인 리포트 말투를 피한다.
- 사용자가 바로 구매 여부를 판단할 수 있도록 짧고 자연스러운 한국어 존댓말을 사용한다.
- confidence, confidenceReasons, feedbackPersonalization, feedbackReliability, 내부 가중치, weighted distance는 사용자 문장에 노출하지 않는다.
- 기준 의류 개수나 데이터 품질을 리포트의 신뢰도 평가로 바꾸지 않는다.
- 사용자 식별자, 원문 코멘트, OCR 원문, raw payload 같은 비공개 데이터를 요청하거나 추측하지 않는다.`;

export const buildFitReportNarrativeInput = (reportInput: FitReportInput) => ({
  locale: reportInput.locale,
  reportStyle: reportInput.reportStyle,
  recommendation: {
    recommendedSize: reportInput.recommendation.recommendedSize,
    fitScore: reportInput.recommendation.fitScore,
    fitLabel: reportInput.recommendation.fitLabel,
    scoreGapToSecond: reportInput.recommendation.scoreGapToSecond
  },
  explanation: {
    topExplanationFactors: reportInput.explanation.topExplanationFactors.map((factor) => ({
      measurement: factor.measurement,
      label: factor.label,
      diff: factor.diff,
      status: factor.status
    }))
  },
  targetProduct: reportInput.targetProduct,
  measurements: reportInput.measurements.map((measurement) => ({
    key: measurement.key,
    label: measurement.label,
    ideal: measurement.ideal,
    product: measurement.product,
    diff: measurement.diff,
    unit: measurement.unit,
    status: measurement.status
  })),
  sizeScores: reportInput.sizeScores.map((size) => ({
    sizeLabel: size.sizeLabel,
    fitScore: size.fitScore,
    fitLabel: size.fitLabel
  })),
  sizeOptions: reportInput.sizeOptions.map((size) => ({
    sizeLabel: size.sizeLabel,
    fitScore: size.fitScore,
    fitLabel: size.fitLabel,
    measurements: size.measurements.map((measurement) => ({
      key: measurement.key,
      label: measurement.label,
      ideal: measurement.ideal,
      product: measurement.product,
      diff: measurement.diff,
      status: measurement.status
    }))
  }))
});

export const buildFitReportPrompt = (reportInput: FitReportInput): string => `${FIT_REPORT_SYSTEM_PROMPT}

아래 JSON은 Coordit Fit Score Engine의 계산 결과다.
원본 DB row, 사용자 피드백 원문, OCR 원문, raw payload, private identifier는 포함하지 않은 계산 요약이다.
다음 순서로 내부적으로 판단한 뒤 최종 JSON만 출력해라.

판단 순서:
1. 추천 사이즈에서 가장 눈에 띄는 부위 하나를 먼저 고르고, 맞는 부위와 다른 부위를 구분한다.
2. measurements의 각 부위를 기준 수치와 상품 수치, 부호가 있는 차이, 상태를 함께 읽는다.
3. sizeOptions에 있는 다른 사이즈는 실제 부위별 차이까지 비교한다. sizeScores만 있는 후보의 실측이나 착용감은 추측하지 않는다.
4. 추천 사이즈의 장점과 감수해야 할 점을 함께 말하고, 취향에 따른 대안을 제시한다.
5. 실제 데이터로 확인할 수 없는 항목만 구매 전 확인 사항으로 분리한다.

요구사항:
1. title은 "M 가슴단면이 타이트할 수 있어요"처럼 결론부터 말한다. "정밀 핏 리포트" 같은 제목은 쓰지 않는다.
2. summary는 빈 줄로 나눈 정확히 세 개의 짧은 문단으로 작성한다: 결론 한 문장, 기준과의 핵심 차이 한 문장, 실제 선택 장면 한 문장.
3. summary에는 가장 중요한 부위만 기준 수치와 차이를 쓸 수 있다. 나머지 수치 나열은 금지한다.
4. measurementAnalysis에는 measurements의 모든 부위를 입력 순서대로 빠짐없이 한 항목씩 작성한다.
5. 각 부위는 정확히 두 문장으로 작성한다: 첫 문장은 기준·상품·cm 차이와 방향, 둘째 문장은 예상되는 착용감 또는 실루엣이다.
6. 값이 유사 범위여도 차이가 0이 아니라면 작아지는 방향인지 커지는 방향인지 문장에 반영한다.
7. recommendationReason은 정확히 세 문장으로 작성한다: 추천 사이즈의 이점과 타협점, 실제 실측이 있는 가장 가까운 대안의 변화, 취향별 최종 선택.
8. 대안의 실측이 입력에 없으면 그 대안이 더 편하거나 더 타이트하다고 말하지 말고, 점수만 비교하거나 상세 치수 확인을 권한다.
9. explanation.topExplanationFactors가 있으면 판단에 크게 작용한 부위를 우선 설명하되 내부 계산 용어를 노출하지 마라.
10. cautions는 소재·신축성·레이어링처럼 실제 데이터로 확인할 수 없는 구매 전 확인 사항만 최대 2개 작성해라.
11. nextActions는 사용자가 상품 상세나 보유 의류에서 실제로 확인할 수 있는 구체적인 행동만 최대 2개 작성해라.
12. confidence, 신뢰도, 피드백, 데이터 품질, 기준 의류 개수에 대한 평가는 어떤 필드에도 쓰지 마라.
13. JSON에 없는 숫자는 만들지 마라.
14. 모든 문단은 서로 다른 역할을 가져야 하며 같은 수치와 결론을 불필요하게 반복하지 마라.
15. 출력은 아래 JSON 형식으로만 해라.

출력 형식:
{
  "title": "...",
  "summary": "...",
  "recommendationReason": "...",
  "measurementAnalysis": [
    { "measurement": "...", "text": "..." }
  ],
  "cautions": ["..."],
  "nextActions": ["..."]
}

입력 JSON:
${JSON.stringify(buildFitReportNarrativeInput(reportInput), null, 2)}`;
