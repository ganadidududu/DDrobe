# 상품 URL 가져오기

Coordit 백엔드는 공개 상품 페이지 한 건을 Playwright로 열고 구조화 데이터, 공개 JSON 응답, DOM 순서로 분석한다. 분석 결과는 미리보기로만 반환되며 사용자가 확인하기 전에는 상품 테이블에 저장하지 않는다.

## 설치와 실행

```bash
cd backend
npm install
npx playwright install chromium
npm run dev
```

Linux 컨테이너에서는 `npx playwright install --with-deps chromium`을 사용한다. Render, Railway, Fly.io, Docker에서는 Playwright의 공식 Jammy 이미지를 기반 이미지로 사용하거나 빌드 단계에서 위 명령으로 OS 의존성과 Chromium을 함께 설치해야 한다. Chromium 실행에 필요한 메모리와 `/dev/shm` 공간을 확보하고, 여러 서버 인스턴스가 같은 도메인을 동시에 과도하게 호출하지 않도록 인스턴스 수와 `MAX_CONCURRENT_PAGES`를 조정한다.

필수 Supabase 설정 외에 [backend/.env.example](../backend/.env.example)의 크롤링 제한값을 환경에 맞게 설정한다. 운영에서는 `USER_AGENT`에 서비스 식별자와 연락 가능한 정책 페이지를 사용하는 것이 좋다.

## 미리보기 API

인증된 사용자가 호출한다.

```bash
curl -X POST http://localhost:4000/api/v1/products/import-url/preview \
  -H 'Authorization: Bearer SUPABASE_ACCESS_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{
    "url": "https://www.musinsa.com/products/1234567",
    "includeImages": true,
    "includeDetailImages": false
  }'
```

성공 응답은 `source`, `product`, `images`, `options`, 원본 순서를 보존한 `sizeChart.rawHeaders/rawRows`, 정규화된 `sizeChart.normalizedRows`, 필드별 출처와 경고를 포함한다. 사이즈표가 없으면 HTTP 성공과 `partial: true`를 반환한다. 이미지형 사이즈표만 발견되면 `requiresOcr: true`, `ocrAvailable: false`, `sizeChartImage`를 반환한다.

지원 대상은 무신사, 29CM, 에이블리, W Concept, 네이버 스마트스토어/브랜드스토어, 지그재그다. 공통 추출기는 일반 표와 행·열이 뒤집힌 표, 상세설명에 적힌 치수 문장, hydration/public JSON 내부의 상세 HTML, 사이즈표 이미지를 순서대로 분석한다. W Concept의 기존 `/Product/{id}` 주소는 접근 가능한 모바일 상품 페이지로 내부 변환하되 응답에는 사용자가 입력한 원본 URL을 유지한다.

사이트 지원과 개별 상품의 사이즈표 존재 여부는 다르다. 판매자가 치수를 등록하지 않았거나 이미지만 제공한 상품은 각각 `partial: true` 또는 `requiresOcr: true`가 될 수 있다. 쇼핑몰이 401/403/429, CAPTCHA, 로그인으로 자동 접근을 제한하면 우회하지 않고 `SITE_BLOCKED_REQUEST` 또는 `RATE_LIMITED`를 반환한다.

실패 응답 예:

```json
{
  "success": false,
  "error": {
    "code": "BLOCKED_PRIVATE_NETWORK",
    "message": "내부 네트워크 주소는 사용할 수 없습니다.",
    "retryable": false
  },
  "partialData": null
}
```

## 사용자 확인 후 저장

기존 상품 API를 재사용한다. 앱은 미리보기 값을 수정 가능한 폼에 채운 후 사용자가 확인하면 상품을 먼저 생성하고 각 정규화 사이즈를 저장한다.

```bash
curl -X POST http://localhost:4000/external-products \
  -H 'Authorization: Bearer SUPABASE_ACCESS_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{
    "productName": "수정된 상품명",
    "brand": "브랜드",
    "mallName": "musinsa",
    "productUrl": "https://www.musinsa.com/products/1234567",
    "sourceProductId": "1234567",
    "category": "tshirt",
    "fitType": "regular",
    "imageUrl": "https://cdn.example.com/product.jpg",
    "rawCategory": "상의 > 반소매 티셔츠",
    "normalizedCategory": "TOP",
    "importedFromUrl": true,
    "importMetadata": {
      "userEdited": true,
      "crawledAt": "2026-07-26T10:00:00.000Z"
    },
    "rawProductData": {
      "rawHeaders": ["사이즈", "총장", "가슴단면"],
      "rawRows": [["M", "70", "56"]]
    }
  }'
```

반환된 상품 ID로 사이즈를 저장한다.

```bash
curl -X POST http://localhost:4000/external-products/PRODUCT_ID/sizes \
  -H 'Authorization: Bearer SUPABASE_ACCESS_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{
    "sizeLabel": "M",
    "totalLength": 70,
    "chestWidth": 56,
    "measurementSource": "url",
    "parsingStatus": "parsed",
    "extractionConfidence": 0.95,
    "rawSizeData": {"총장": "70", "가슴단면": "56"}
  }'
```

`DefaultFitScoreProductMeasurementMapper`는 cm 단위이며 신뢰도가 0.85 이상인 단일 실측값만 기존 Fit Score 측정 키로 변환한다. 단위 미확인, 범위, 둘레, 불명확한 값은 계산에서 제외된다. 저장된 `external_product_sizes`는 기존 `/fit/recommend` 흐름에서 그대로 사용된다.

## 데이터베이스

기존 환경에는 다음 마이그레이션을 적용한다.

```bash
psql "$DATABASE_URL" -f supabase/migrations/20260726_add_product_url_import.sql
```

새 환경은 기존 순서대로 `schema.sql`, `indexes.sql`, `rls.sql`을 적용한다. 미리보기 자체는 저장하지 않는다. `product_import_logs`는 운영 로그 확장을 위한 최소 스키마이며 현재 요청 성공의 필수 의존성이 아니다.

## 테스트

```bash
cd backend
npm run typecheck
npm run test:product-import
```

테스트는 외부 쇼핑몰에 접속하지 않고 HTML과 JSON fixture로 URL 차단, 어댑터 판별, JSON-LD/Next.js 데이터, 이미지 중복 제거, 테이블 병합 셀, 원본 순서, 단위와 측정 종류를 검사한다.

## 어댑터 추가

`ProductCrawlerAdapter`를 구현하고 `productCrawlerAdapters`의 Generic 어댑터 앞에 등록한다. `supports`는 정확한 호스트 또는 하위 도메인만 허용해야 한다. 확인하지 않은 비공개 API나 선택자를 추가하지 않는다. 공통 구조화 데이터·네트워크·DOM 추출로 부족하고 실제 공개 페이지에서 확인한 경우에만 해당 사이트 전용 파서를 추가한다.

## 실패 디버깅

- `BLOCKED_PRIVATE_NETWORK`: 최초 URL, DNS 결과 또는 리다이렉트가 내부 주소를 가리킨다.
- `SITE_BLOCKED_REQUEST`: 공개 페이지가 401/403을 반환했거나 리다이렉트 제한을 초과했다. CAPTCHA, 로그인, 봇 탐지는 우회하지 않는다.
- `PRODUCT_NAME_NOT_FOUND`: 저장된 HTML fixture로 구조화 데이터와 공개 DOM이 변경됐는지 확인한다.
- `RESPONSE_TOO_LARGE`: HTML 또는 JSON 제한을 조정하기 전에 해당 응답이 정말 상품 데이터인지 확인한다.
- `CRAWL_TIMEOUT`: 로컬에서 Chromium 설치 여부와 쇼핑몰 응답 시간을 확인한 후 제한을 조정한다.

쿠키와 사용자 인증 정보는 쇼핑몰 요청에 전달하지 않으며, 브라우저 Context와 Page는 요청마다 분리되어 종료된다.
