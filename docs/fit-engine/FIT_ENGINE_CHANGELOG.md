# Fit Engine 변경 이력

문서 상태: 최신  
기준일: 2026-07-03
관련 문서: `fit-engine/FIT_ENGINE.md`

이 문서는 추천 엔진의 변화와 다음 개선 후보를 기록합니다. 현재 실제 동작 기준 문서는 `FIT_ENGINE.md`입니다.

## v1.6 Measurement-only Recommendation

현재 코드에 반영된 주요 개선입니다.

- `ALGORITHM_VERSION = "mvp_rule_v1_6"`로 변경
- fit score와 추천 사이즈는 기준 의류 실측, 상품 실측, 카테고리/핏 타입만으로 계산
- 사용자 피드백과 기준 샘플 수는 점수·추천 사이즈·리포트 품질 평가에 반영하지 않음
- 피드백은 구매 후 기록 및 향후 오프라인 분석용 데이터로만 유지
- Ollama 공개 리포트 계약을 `fit_report_v5`로 변경하고 신뢰도·피드백·샘플 부족 서술을 제외

## v1.0 MVP Rule Engine

핵심 특징:

- 단일 기준 의류 기반 추천
- 기준 의류 실측값과 외부 상품 사이즈표 비교
- 부위별 차이를 weighted distance로 변환
- distance를 0~100 fit score로 변환
- 최고 점수 사이즈 추천
- 추천 결과 DB 저장

## v1.1 Multiple References

현재 코드에 반영된 주요 개선입니다.

- `referenceClothingIds`로 여러 기준 의류 입력 가능
- 각 기준 의류의 `preference_score`를 가중치로 사용
- 전체 외부 상품 사이즈 후보별 점수 반환
- 부위별 설명과 상태 반환
- `recommendationConfidence` 반환
- 카테고리 호환성 검사 강화

## v1.2 Reference Variance Weighting & Outseam Migration

현재 코드에 반영된 주요 개선입니다.

- 여러 기준 의류 사용 시 reference 간 표준편차 기반 동적 가중치 적용
- 기준 의류들 사이에서 변화 폭이 작은 측정 항목을 사용자가 중요하게 여기는 요소로 해석
- 표준편차가 작은 측정 항목은 가중치 증가
- 표준편차가 큰 측정 항목은 가중치 감소
- dynamic weight 합이 1이 되도록 정규화
- 추천 결과의 `result_details`에 `baseWeights`, `dynamicWeights`, `referenceVariance`, `weightingStrategy` 저장
- 하의 측정 항목을 `inseam`에서 `outseam`으로 변경
- `outseam`은 MVP 단계에서 바지 전체 기장 비교에 더 직관적인 항목으로 사용

## v1.3 Virtual Reference Profile

현재 코드에 반영된 주요 개선입니다.

- 다중 기준 의류의 개별 점수 평균을 제거하고 가상 100점 핏 프로필 기반 비교로 변경
- `preference_score`와 가중 중앙값을 이용해 항목별 중심값 계산
- Huber 방식의 이상치 완화로 유난히 큰/작은 기준 의류의 영향 축소
- MAD 기반 항목별 허용 오차를 적용해 cm 차이를 정규화
- 가상 프로필과 동일한 후보는 100점을 받을 수 있음
- `result_details`와 API 응답에 `referenceProfile` 저장/반환

## v1.4 Feedback-adjusted Profile

현재 코드에 반영된 주요 개선입니다.

- `actualFitLabel` 기반 사용자/카테고리별 전체 핏 방향 보정 추가
- `partFeedback` 기반 부위별 offset 보정 추가
- 반복적으로 문제가 발생한 부위의 weight multiplier 적용
- `user_feedback.part_feedback` JSONB 컬럼 추가
- 추천 실행 시 최근 피드백을 `feedbackProfile`로 요약
- 추천 결과의 `result_details`와 API 응답에 `feedbackProfile` 저장/반환
- `weightingStrategy = "feedback_adjusted_profile_v1"` 추가

## v1.5 Reliability-gated Confidence Metadata

현재 코드에 반영된 주요 개선입니다.

- `ALGORITHM_VERSION = "mvp_rule_v1_5"`로 변경
- 추천 결과와 후보 사이즈에 선택 필드 `scoreExplanation`, `confidenceBreakdown` 추가
- `result_details.scoreExplanation`에 비교 측정값, 누락 측정값, 2위 후보와의 점수 차이, 정규화 거리, 패널티, 주요 기여 부위, reason code 저장
- `result_details.confidenceBreakdown`에 최종 confidence 근거, 피드백 신뢰도, 상품 실측 데이터 품질 요약 저장
- 피드백 보정은 카테고리 5개 이상, 부위별 3개 이상 등 신뢰도 기준을 통과할 때만 강하게 적용
- 오래된 피드백은 최근 피드백보다 낮게 반영하고, 상충 피드백은 보수적으로 처리
- `measurement_source`, `parsing_status`, `extraction_confidence`는 fit score가 아니라 confidence와 report caveat에 반영
- 저장 형식은 기존 `fit_analysis_results.result_details` JSONB를 사용하므로 no schema migration이 필요하지 않음
- 새 `result_details` 필드는 legacy-tolerant 하며, 과거 row에 설명 메타데이터가 없어도 report builder는 기존 필드로 fallback
- `fit_report_v2`는 confidence reason, missing measurement, data quality, feedback reliability summary를 리포트 입력과 prompt에 포함

## 다음 개선 후보

### v1.7 Measurement Input Normalization

- camelCase 측정값 입력 지원
- cm/mm 단위 정규화
- 문자열 기반 치수 파싱
- 필수 측정값 부족 시 더 명확한 에러 메시지

### v1.8 Feedback-aware Score Adjustment

- 사용자별 confidence calibration
- 피드백 부족 사용자에 대한 cohort fallback
- 충분한 검증 fixture 확보 후 score 자체의 보정 여부 판단

### v1.9 Product Parsing Confidence Expansion

- OCR/URL 파싱 원본 수집과 사용자 확인 workflow 강화
- `measurement_source`별 품질 감사 리포트

### v2.0 Data-driven Fit Model

- 충분한 피드백 데이터 확보 후 ML 또는 통계 기반 보정
- 브랜드별/카테고리별 사이즈 편차 모델링
- 사용자 체형 데이터와 기준 의류 데이터 결합
