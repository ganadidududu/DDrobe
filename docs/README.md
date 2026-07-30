# Coordit Docs

문서 상태: 모바일 MVP 기준 정리본  
기준일: 2026-06-25

## 문서 구조

Coordit 문서는 모바일 앱 MVP 개발 기준으로 최소 구조를 유지한다.

```text
docs/
  README.md
  REFACTOR_ANALYSIS.md
  PRODUCT_OVERVIEW.md
  API_SPEC_MOBILE.md
  DATABASE_SCHEMA.md
  FIT_REPORT_OPENROUTER_SPEC.md
  ROADMAP.md
  fit-engine/
    FIT_ENGINE.md
    FIT_ENGINE_CHANGELOG.md
```

## 먼저 읽을 문서

| 보고 싶은 내용 | 문서 |
| --- | --- |
| 제품 기획, 문제 정의, MVP 범위 | `PRODUCT_OVERVIEW.md` |
| 모바일 앱 API | `API_SPEC_MOBILE.md` |
| OpenRouter 핏 리포트 설계 | `FIT_REPORT_OPENROUTER_SPEC.md` |
| 추천 알고리즘 | `fit-engine/FIT_ENGINE.md` |
| 추천 엔진 변경 이력 | `fit-engine/FIT_ENGINE_CHANGELOG.md` |
| DB, 관계, 인덱스, RLS, migration | `DATABASE_SCHEMA.md` |
| 개발 계획 | `ROADMAP.md` |
| 문서 리팩토링 판단 근거 | `REFACTOR_ANALYSIS.md` |

## 문서별 책임

### `PRODUCT_OVERVIEW.md`

Coordit의 제품 정의, 문제, 핵심 가치, 사용자 플로우, 주요 기능, MVP 범위, 향후 확장 방향을 설명한다.

API endpoint, DB schema, Fit Engine 계산식은 설명하지 않는다.

### `API_SPEC_MOBILE.md`

모바일 앱 개발에 필요한 API를 사용자 플로우와 기능 중심으로 설명한다.

SQL, 테이블 상세, repository/service/controller 구조는 설명하지 않는다.

### `fit-engine/FIT_ENGINE.md`

추천 엔진의 입력, 계산 과정, 표준편차 기반 가중치, 다중 기준 의류, fit score, confidence, feedback 구조를 설명한다.

API 사용법과 DB schema는 설명하지 않는다.

### `FIT_REPORT_OPENROUTER_SPEC.md`

Fit Score Engine 결과값을 OpenRouter JSON Schema 리포트와 그래프 데이터로 변환하는 기준을 설명한다.

Fit score 계산 자체는 설명하지 않고, 계산된 수치를 어떻게 리포트 입력값, 차트 데이터, LLM prompt로 구성할지 설명한다.

### `DATABASE_SCHEMA.md`

Supabase PostgreSQL의 ERD, table, relation, index, RLS, migration을 설명한다.

API 플로우와 화면 명세는 설명하지 않는다.

### `ROADMAP.md`

현재 상태와 향후 개발 계획을 설명한다.

API 상세, DB 상세, 알고리즘 계산식은 설명하지 않는다.

## 문서 관리 원칙

- 한 문서는 하나의 책임만 가진다.
- 같은 내용을 여러 문서에서 반복하지 않는다.
- 제품 설명은 product 문서에 둔다.
- API 설명은 api 문서에 둔다.
- DB 설명은 database 문서에 둔다.
- 알고리즘 설명은 fit-engine 문서에 둔다.
- 개발 계획은 roadmap 문서에 둔다.
- 코드 변경이 발생하면 관련 책임 문서 하나만 갱신한다.
