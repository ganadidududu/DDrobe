# Fit Report with OpenRouter Spec

문서 상태: 현행 계약
기준일: 2026-07-28
엔진 버전: `mvp_rule_v1_6`
프롬프트 버전: `fit_report_v5`

## 1. 목적

Fit Score Engine이 계산한 추천 사이즈와 실측 차이를 OpenRouter의
`google/gemini-2.5-flash`가 자연스러운 한국어
구매 리포트로 설명한다. LLM은 계산기가 아니라 설명 계층이다.

- fit score, 추천 사이즈, 부위별 차이는 엔진 결과를 그대로 사용한다.
- 다른 사이즈의 점수도 함께 비교한다.
- 기준 의류와 상품의 모든 비교 가능한 부위를 빠짐없이 설명한다.
- confidence, 신뢰도, 피드백, 데이터 품질, 기준 의류 개수는 사용자용 품질
  판단이나 추천 근거로 노출하지 않는다.

## 2. 책임 경계

Fit Score Engine:

- 기준 의류의 가상 실측 프로필 생성
- 상품의 모든 사이즈 점수 계산
- 추천 사이즈 선택
- 기준/상품 실측과 signed diff 계산
- 차트용 숫자 시리즈 생성

OpenRouter:

- 제공된 수치의 의미를 자연스러운 한국어로 설명
- 폭과 길이의 장단점을 구분
- 모든 사이즈 점수와 부위별 차이를 종합해 추천 이유 작성
- 소재, 신축성, 레이어링처럼 확정할 수 없는 항목을 구매 전 확인 사항으로 분리

OpenRouter가 하면 안 되는 일:

- fit score, 추천 사이즈, diff 재계산
- 입력에 없는 숫자·신체 정보·상품 정보 생성
- confidence 또는 기준 샘플 수를 리포트 품질로 해석
- 사용자 피드백이나 데이터 품질을 추천 근거로 사용

## 3. LLM 입력 계약

`buildFitReportNarrativeInput`은 다음 필드만 OpenRouter에 전달한다.

```json
{
  "locale": "ko-KR",
  "reportStyle": "concise_but_explanatory",
  "recommendation": {
    "recommendedSize": "L",
    "fitScore": 92,
    "fitLabel": "good_fit",
    "scoreGapToSecond": 8
  },
  "explanation": {
    "topExplanationFactors": [
      {
        "measurement": "chest_width",
        "label": "가슴단면",
        "diff": 1,
        "status": "slightly_large"
      }
    ]
  },
  "targetProduct": {
    "productName": "Linen Shirt",
    "brand": "Brand",
    "mallName": "29CM",
    "category": "shirt",
    "fitType": "regular",
    "selectedSizeLabel": "L",
    "recommendedSizeLabel": "L"
  },
  "measurements": [
    {
      "key": "chest_width",
      "label": "가슴단면",
      "ideal": 58,
      "product": 59,
      "diff": 1,
      "unit": "cm",
      "status": "slightly_large"
    }
  ],
  "sizeScores": [
    {
      "sizeLabel": "L",
      "fitScore": 92,
      "fitLabel": "good_fit"
    }
  ]
}
```

다음 값은 내부 디버그 객체에 남아 있을 수 있지만 OpenRouter 입력에는 포함하지 않는다.

- `recommendationConfidence`, `confidenceReasons`
- `feedbackPersonalization`, `feedbackReliability`
- 내부 가중치와 weighted distance
- 원본 DB row, 사용자 피드백 원문, OCR 원문, raw payload
- 사용자 또는 데이터베이스 식별자

## 4. 출력 계약

OpenRouter는 strict JSON Schema로 다음 JSON만 반환한다.

```json
{
  "title": "L 사이즈 정밀 핏 리포트",
  "summary": "...",
  "recommendationReason": "...",
  "measurementAnalysis": [
    {
      "measurement": "가슴단면",
      "text": "..."
    }
  ],
  "cautions": ["..."],
  "nextActions": ["..."]
}
```

작성 기준:

- `summary`: 추천 사이즈, fit score, 전체 실루엣과 핵심 장단점을 4~5문장으로 작성
- `recommendationReason`: 다른 모든 사이즈 점수와 부위별 균형을 6~9문장으로 설명
- `measurementAnalysis`: 모든 입력 부위를 순서대로 작성하고 기준값, 상품값,
  signed diff와 착용 의미를 포함
- `cautions`: 데이터로 확정할 수 없는 구매 전 확인 사항 최대 2개
- `nextActions`: 상품 상세나 보유 의류에서 확인할 수 있는 행동 최대 2개

`fitDnaSummary`와 `feedbackPersonalization`은 `fit_report_v5` 공개 출력 필드가 아니다.

## 5. 출력 보정

백엔드는 OpenRouter의 structured output을 그대로 신뢰하지 않는다.

- 부위별 문장에 입력과 다른 숫자가 있으면 해당 부위를 측정 기반 문장으로 교체한다.
- 입력에 없는 숫자가 요약·추천 이유·확인 사항에 있으면 해당 섹션을 fallback으로 교체한다.
- 지나치게 짧은 요약 또는 추천 이유는 상세 fallback 문장으로 교체한다.
- 신뢰도, 피드백, 기준 샘플 부족 서술이 있으면 해당 섹션을 교체한다.
- cm 수치가 요약이나 추천 이유에 섞이면 부위·숫자 오귀속을 막기 위해 해당 핵심
  서술을 교체한다. cm 수치는 부위별 분석에서만 허용한다.
- 누락된 부위는 모두 측정 기반 문장으로 채운다.

작성 목표는 위 문장 범위이며, 출력 보정의 하한은 summary 4문장,
recommendationReason 6문장, 부위별 분석 3문장이다. 목표보다 긴 문장은 다른
안전성·숫자 조건을 만족하면 불필요한 재시도를 피하기 위해 허용한다.

OpenRouter가 만든 `summary`와 `recommendationReason`에 각각 안전한 모델 문장이 하나
이상 있으면 그 문장을 보존하고, 제거되거나 부족한 문장만 deterministic 문장으로
보완한 뒤 `source: "openrouter"`를 반환한다. 두 핵심 서술 중 하나라도 보존할 수 있는
모델 문장이 없거나 HTTP 호출·JSON 파싱이 실패하면 백엔드는 전체 deterministic
fallback과 `source: "fallback"`을 반환한다. iOS Fit Lab은 LLM 작성까지 완료된
리포트만 완료 화면으로 표시하므로 `fallback`을 최종 리포트로 열지 않고
로딩·재시도 상태를 유지한다.

## 6. API 계약

Endpoint:

```http
POST /fit-analysis-results/:id/report
```

요청 예:

```json
{
  "selectedSizeLabel": "L",
  "style": "concise_but_explanatory",
  "includeDebug": false
}
```

응답 예:

```json
{
  "fitAnalysisResultId": "uuid",
  "source": "openrouter",
  "modelName": "google/gemini-2.5-flash",
  "promptVersion": "fit_report_v5",
  "report": {
    "title": "L 사이즈 정밀 핏 리포트",
    "summary": "...",
    "recommendationReason": "...",
    "measurementAnalysis": [],
    "cautions": [],
    "nextActions": []
  },
  "chartData": {
    "idealVsProduct": [],
    "differenceBar": [],
    "sizeScoreRanking": [],
    "feedbackAdjustment": []
  }
}
```

`includeDebug = true`일 때만 `reportInput`과 최종 prompt를 추가한다. 모바일
클라이언트는 디버그 필드 없이 `report`와 `chartData`만으로 렌더링해야 한다.

## 7. 차트 계약

차트는 LLM이 생성하지 않는다.

- `idealVsProduct`: 기준 실측과 상품 실측
- `differenceBar`: 0을 중심으로 한 signed cm 차이
- `sizeScoreRanking`: 모든 후보 사이즈의 0~100 fit score
- `feedbackAdjustment`: 기존 디버그 호환 필드이며 사용자 리포트 품질 판단에 사용하지 않음

negative diff는 왼쪽, positive diff는 오른쪽으로 표시한다. 정확히 0이면 중앙 마크를
사용한다. 색상과 무관하게 텍스트로 측정명, 기준값, 상품값, signed diff를 함께 제공한다.

## 8. 환경 변수

- `OPENROUTER_API_KEY`: OpenRouter API 키
- `OPENROUTER_MODEL`: 기본값 `google/gemini-2.5-flash`
- `OPENROUTER_TIMEOUT_MS`: 기본값 `20000`

OpenRouter API 키가 없거나 호출·응답 검증에 실패해도 동일한 숫자 계약을 사용하는
deterministic fallback 리포트가 생성되어야 한다.
