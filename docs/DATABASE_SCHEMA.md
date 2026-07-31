# Coordit Database Schema

문서 상태: 모바일 MVP 기준 정리본  
기준일: 2026-06-25  
기준 SQL: `supabase/schema.sql`, `supabase/indexes.sql`, `supabase/rls.sql`

## 1. 문서 목적

이 문서는 Coordit의 Supabase PostgreSQL 스키마, 관계, 인덱스, RLS, migration 정보를 정리한다.

이 문서는 API 사용법, 화면 흐름, Fit Engine 계산식을 설명하지 않는다.

## 2. 적용 순서

신규 Supabase 프로젝트에는 다음 순서로 SQL을 적용한다.

1. `supabase/schema.sql`
2. `supabase/indexes.sql`
3. `supabase/rls.sql`
4. `supabase/seed.sql` 선택

## 3. ERD

```text
auth.users
  └─ public.users
      ├─ body_measurements
      ├─ clothing_items
      │   ├─ clothing_sizes
      │   └─ reference_clothing
      ├─ external_products
      │   └─ external_product_sizes
      ├─ fit_analysis_results
      ├─ user_feedback
      └─ recommendation_logs
```

## 4. Tables

### `users`

Supabase Auth 사용자와 연결되는 public profile이다.

주요 컬럼:

- `id`
- `email`
- `display_name`
- `gender`
- `birth_year`
- `created_at`
- `updated_at`

관계:

- `id`는 `auth.users(id)`를 참조한다.

### `body_measurements`

사용자의 신체 치수 이력을 저장한다.

주요 컬럼:

- `id`
- `user_id`
- `height_cm`
- `weight_kg`
- `shoulder_width`
- `outseam`
- `raw_data`
- `created_at`

관계:

- `user_id`는 `users(id)`를 참조한다.

### `clothing_items`

사용자가 보유한 의류의 기본 정보를 저장한다.

주요 컬럼:

- `id`
- `user_id`
- `name`
- `brand`
- `category`
- `fit_type`
- `size_label`
- `notes`
- `image_url`
- `raw_product_data`
- `created_at`
- `updated_at`

관계:

- `user_id`는 `users(id)`를 참조한다.
- `clothing_sizes.clothing_item_id`에서 참조된다.
- `reference_clothing.clothing_item_id`에서 참조된다.

### `clothing_sizes`

보유 의류의 실측값을 저장한다.

주요 컬럼:

- `id`
- `user_id`
- `clothing_item_id`
- `size_label`
- `total_length`
- `shoulder_width`
- `chest_width`
- `sleeve_length`
- `waist_width`
- `hip_width`
- `rise`
- `outseam`
- `raw_measurements`
- `created_at`
- `updated_at`

관계:

- `user_id`는 `users(id)`를 참조한다.
- `clothing_item_id`는 `clothing_items(id)`를 참조한다.

### `reference_clothing`

추천 기준으로 선택된 보유 의류를 저장한다.

주요 컬럼:

- `id`
- `user_id`
- `clothing_item_id`
- `nickname`
- `category`
- `fit_type`
- `preference_score`
- `is_active`
- `notes`
- `created_at`
- `updated_at`

관계:

- `user_id`는 `users(id)`를 참조한다.
- `clothing_item_id`는 `clothing_items(id)`를 참조한다.
- `fit_analysis_results.reference_clothing_id`에서 참조된다.

제약:

- `unique (user_id, clothing_item_id)`
- `preference_score between 1 and 100`

### `external_products`

구매하려는 외부 쇼핑 상품을 저장한다.

주요 컬럼:

- `id`
- `user_id`
- `product_name`
- `brand`
- `mall_name`
- `product_url`
- `category`
- `fit_type`
- `image_url`
- `raw_product_data`
- `created_at`
- `updated_at`

관계:

- `user_id`는 `users(id)`를 참조한다.
- `external_product_sizes.external_product_id`에서 참조된다.
- `fit_analysis_results.external_product_id`에서 참조된다.
- `recommendation_logs.external_product_id`에서 참조된다.

### `external_product_sizes`

외부 상품의 사이즈표 row를 저장한다.

주요 컬럼:

- `id`
- `user_id`
- `external_product_id`
- `size_label`
- `total_length`
- `shoulder_width`
- `chest_width`
- `sleeve_length`
- `waist_width`
- `hip_width`
- `rise`
- `outseam`
- `raw_size_data`
- `parsing_status`
- `measurement_source`
- `extracted_text`
- `extraction_confidence`
- `created_at`
- `updated_at`

관계:

- `user_id`는 `users(id)`를 참조한다.
- `external_product_id`는 `external_products(id)`를 참조한다.
- `fit_analysis_results.recommended_external_product_size_id`에서 참조된다.

OCR/URL 파싱 확장 준비 컬럼:

- `raw_size_data`
- `parsing_status`
- `measurement_source`
- `extracted_text`
- `extraction_confidence`

### `fit_analysis_results`

추천 실행 결과를 저장한다.

주요 컬럼:

- `id`
- `user_id`
- `reference_clothing_id`
- `external_product_id`
- `recommended_external_product_size_id`
- `recommended_size_label`
- `fit_score`
- `fit_label`
- `fit_comment`
- `weighted_fit_distance`
- `algorithm_version`
- `recommendation_confidence`
- `result_details`
- `created_at`

관계:

- `user_id`는 `users(id)`를 참조한다.
- `reference_clothing_id`는 `reference_clothing(id)`를 참조한다.
- `external_product_id`는 `external_products(id)`를 참조한다.
- `recommended_external_product_size_id`는 `external_product_sizes(id)`를 참조한다.
- `user_feedback.fit_analysis_result_id`에서 참조된다.
- `recommendation_logs.fit_analysis_result_id`에서 참조된다.

주의:

- 다중 기준 의류를 사용해도 `reference_clothing_id`에는 첫 번째 기준 의류가 저장된다.
- 전체 기준 의류 목록과 엔진 메타데이터는 `result_details`에 저장된다.
- Fit Engine `mvp_rule_v1_7`의 `scoreExplanation`, `confidenceBreakdown`,
  피드백 신뢰도, 상품 실측 데이터 품질 요약도 `result_details` JSONB에 저장된다.
- 이 확장은 no schema migration 변경이다. 새 필드는 legacy-tolerant optional
  metadata이며, 과거 row에 없어도 API와 report builder가 기존 필드로 fallback한다.

### `user_feedback`

추천 결과에 대한 실제 구매/착용 피드백을 저장한다.

주요 컬럼:

- `id`
- `user_id`
- `fit_analysis_result_id`
- `purchased_size_label`
- `actual_fit_rating`
- `actual_fit_label`
- `part_feedback`
- `comment`
- `raw_data`
- `created_at`

관계:

- `user_id`는 `users(id)`를 참조한다.
- `fit_analysis_result_id`는 `fit_analysis_results(id)`를 참조한다.

`part_feedback`은 부위별 실제 핏 평가를 저장하는 JSON 객체다.

예:

```json
{
  "chest_width": "too_small",
  "sleeve_length": "good"
}
```

허용 label:

- `too_small`
- `slightly_small`
- `good`
- `slightly_large`
- `too_large`

### `recommendation_logs`

추천 노출, 클릭, 구매 이벤트를 저장한다.

주요 컬럼:

- `id`
- `user_id`
- `fit_analysis_result_id`
- `external_product_id`
- `recommended_size_label`
- `event_type`
- `clicked_at`
- `purchased_at`
- `algorithm_version`
- `raw_data`
- `created_at`

관계:

- `user_id`는 `users(id)`를 참조한다.
- `fit_analysis_result_id`는 `fit_analysis_results(id)`를 참조한다.
- `external_product_id`는 `external_products(id)`를 참조한다.

## 5. Measurement Fields

현재 스키마의 주요 실측값 필드는 다음이다.

- `total_length`
- `shoulder_width`
- `chest_width`
- `sleeve_length`
- `waist_width`
- `hip_width`
- `rise`
- `outseam`

하의 길이 비교는 `outseam`을 기준으로 한다.

## 6. Categories and Fit Types

카테고리:

- `tshirt`
- `shirt`
- `sweatshirt`
- `hoodie`
- `knit`
- `jacket`
- `coat`
- `pants`
- `jeans`
- `shorts`
- `skirt`

Fit type:

- `slim`
- `regular`
- `relaxed`
- `oversized`

## 7. Indexes

현재 인덱스는 `supabase/indexes.sql`에 있다.

- `idx_body_measurements_user_id`
- `idx_clothing_items_user_category`
- `idx_clothing_sizes_item_id`
- `idx_reference_clothing_user_active`
- `idx_reference_clothing_user_category`
- `idx_external_products_user_category`
- `idx_external_product_sizes_product_id`
- `idx_fit_results_user_created_at`
- `idx_feedback_user_id`
- `idx_recommendation_logs_user_created_at`

추가 검토 후보:

- `clothing_sizes(user_id, clothing_item_id)`
- `external_product_sizes(user_id, external_product_id)`

## 8. RLS

`supabase/rls.sql`은 user-owned 테이블에 RLS를 활성화한다.

RLS 대상:

- `users`
- `body_measurements`
- `clothing_items`
- `clothing_sizes`
- `reference_clothing`
- `external_products`
- `external_product_sizes`
- `fit_analysis_results`
- `user_feedback`
- `recommendation_logs`

기본 정책:

- 대부분의 테이블은 `auth.uid() = user_id`
- `users` 테이블은 `auth.uid() = id`

주의:

- 백엔드는 service role key를 사용하므로 RLS를 우회할 수 있다.
- API 코드에서는 모든 user-owned query에 user scope 필터가 반드시 필요하다.
- 클라이언트가 전달한 `user_id`는 신뢰하지 않는다.

## 9. Migration

현재 migration 파일:

- `supabase/migrations/20260511_add_styling_looks.sql`
- `supabase/migrations/20260522_rename_inseam_to_outseam.sql`
- `supabase/migrations/20260629_add_part_feedback_to_user_feedback.sql`

Migration notes:

- Fit Engine v1.2에서 하의 길이 측정 항목을 `inseam`에서 `outseam`으로 변경했다.
- 기존 운영 데이터가 있다면 `inseam` 값을 `outseam`으로 이전할지 별도 판단이 필요하다.
- Styling 확장용 테이블은 별도 migration에 포함되어 있다.
- MVP+2 피드백 보정을 위해 `user_feedback.part_feedback` JSONB 컬럼을 추가했다.
- Fit Engine `mvp_rule_v1_7` 및 report prompt `fit_report_v6`는 새 SQL migration이 없다. 설명/진단 메타데이터는 `fit_analysis_results.result_details` JSONB에 저장되고 legacy-tolerant 하게 읽힌다. 피드백 메타데이터는 현재 fit score나 사용자 리포트 서술을 변경하지 않는다.
