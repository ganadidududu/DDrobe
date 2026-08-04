# Coordit 백엔드 스테이징 배포 안내

이 문서는 Coordit 백엔드를 **스테이징(staging)** 환경에 올리는 절차다. 스테이징은 실제 사용자에게 공개하기 전에 팀이 확인하는 별도 환경이다. 이 절차는 현재 API 한 개를 Google Cloud Run에 배포한다. GitHub Actions의 CI는 검증만 하며, 이 문서의 어느 단계에서도 자동 배포하거나 클라우드 자원을 만들지 않는다.

## 시작 전: 누가 무엇을 만드는가

다음은 프로젝트 소유자 또는 권한을 받은 사람이 Google Cloud 콘솔과 Supabase 대시보드에서 직접 만든다.

- 별도 GCP 프로젝트와 결제(Billing) 연결
- 별도 Supabase 스테이징 프로젝트(프로덕션 프로젝트와 공유하지 않음)
- Google Cloud Run 및 Artifact Registry 사용 권한, 그리고 해당 프로젝트의 Secret Manager 비밀

Coordit 저장소와 CI는 위 자원을 생성하지 않으며, 이 문서에도 실제 비밀값을 붙여 넣지 않는다. 비밀값은 Secret Manager 또는 로컬의 Git 추적 제외 파일에만 입력한다. 채팅, 이슈, 커밋, `.env.example`, CI YAML에 실제 값을 넣지 않는다.

준비할 계정은 GitHub, Google Cloud, Supabase다. Google 계정에는 최소한 Cloud Run을 배포할 권한과 Artifact Registry에 이미지를 올릴 권한이 필요하다. 권한 이름이 조직마다 다르면 관리자에게 “스테이징 Cloud Run 서비스 배포와 Artifact Registry 이미지 푸시 권한”을 요청한다.

## 배포 경로와 첫 설정값

이 안내는 **컨테이너 이미지 → Artifact Registry → Cloud Run** 경로만 사용한다. `gcloud run deploy --source`는 선택하지 않는다. 이렇게 하면 CI와 같은 Dockerfile을 로컬에서 먼저 확인하고, 배포할 정확한 이미지 태그를 롤백에 재사용할 수 있다.

처음에는 아래 값으로 시작한다. `지역(region)`은 Supabase와 가까운 곳을 골라 한 번 정한 뒤 일관되게 사용한다. 아래 숫자는 서비스 규모와 Playwright 사용량을 관찰해 조정하는 값이다.

| 항목 | 초기값 | 의미 |
| --- | --- | --- |
| 서비스 이름 | `coordit-backend-staging` | Cloud Run에 표시되는 API 이름 |
| 리전 | `asia-northeast3` | 서울 리전. Supabase 위치가 다르면 더 가까운 리전을 선택 |
| 메모리 | `1Gi` | Playwright 포함 API의 보수적인 시작값; 측정 후 조정 |
| 동시성 | `1` | 한 인스턴스가 동시에 처리할 요청 수. URL 가져오기가 있는 현재 구조에서는 안전한 시작값 |
| 최소 인스턴스 | `0` | 유휴 비용을 줄이는 기본값 |
| 최대 인스턴스 | `2` | 초기 크롤링 부하를 제한하는 시작값 |
| 헬스 엔드포인트 | `/health` | 인증 없이 `{"ok":true,"service":"coordit-backend"}`를 반환하는 확인용 주소 |

`PORT`는 Cloud Run이 컨테이너에 전달하는 포트다. 애플리케이션은 이 값을 사용하도록 구현되어 있으므로 Cloud Run 콘솔의 컨테이너 포트는 `8080`으로 설정하고, `PORT`를 별도 비밀이나 환경변수로 덮어쓰지 않는다.

## 1. GitHub CI가 먼저 통과하는지 확인

1. GitHub에서 대상 브랜치 또는 PR의 **Actions** 탭을 연다.
2. **Backend CI / Validate backend**가 초록색인지 확인한다.
3. 실행 로그에 `npm ci`, `npm run typecheck`, `npm test`, `npm run build`, `docker build`가 모두 성공했는지 확인한다.

이 워크플로는 `backend/**` 또는 `.github/workflows/backend-ci.yml` 변경에만 실행되고, `contents: read` 권한만 갖는다. Google Cloud 인증·시크릿·배포 명령은 포함하지 않는다.

## 2. Google Cloud CLI 설치 및 로그인

터미널에서 [Google Cloud CLI 설치 안내](https://cloud.google.com/sdk/docs/install)를 따라 `gcloud`를 설치한다. 이후 아래의 꺾쇠괄호 항목만 자신의 식별자로 바꿔 실행한다. 실제 비밀값은 이 명령에 넣지 않는다.

```bash
gcloud auth login
gcloud auth application-default login
gcloud projects list
gcloud config set project <GCP_PROJECT_ID>
gcloud config set run/region asia-northeast3
gcloud services enable run.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com
```

마지막 명령은 선택한 GCP 프로젝트에서 필요한 API를 사용 설정한다. 비용과 권한이 걱정되면 실행 전 프로젝트 관리자와 확인한다.

## 3. Supabase 스테이징과 비밀 이름 준비

Supabase 대시보드에서 새 **스테이징 전용** 프로젝트를 만들고, 프로덕션 키나 데이터베이스를 재사용하지 않는다. 데이터베이스가 새 프로젝트인지, 예전에 만든 프로젝트인지에 따라 SQL 적용 방법이 다르다.

### 새 스테이징 프로젝트

저장소의 현재 기본 스키마를 Supabase SQL Editor에서 다음 순서로 한 번씩 실행한다. `supabase/schema.sql`에는 이미 URL 가져오기에 필요한 `external_products.source_url`, `thumbnail_url`, `imported_from_url` 컬럼과 `product_import_logs` 테이블이 포함되어 있다. 따라서 새 프로젝트에 URL 가져오기 마이그레이션이나 과거 마이그레이션을 전부 다시 실행하지 않는다.

1. `supabase/schema.sql`
2. `supabase/indexes.sql`
3. `supabase/rls.sql`
4. 필요할 때만 `supabase/seed.sql` (선택 사항)

### 기존 스테이징 프로젝트

기존 프로젝트를 계속 사용할 때는 현재 테이블에 URL 가져오기 필드가 있는지 먼저 확인한다. 없다면 `supabase/migrations/20260726_add_product_url_import.sql` **하나만** SQL Editor에서 실행한 뒤 `POST /api/v1/products/import-url/preview`를 테스트한다. 이 마이그레이션은 이미 있는 컬럼·테이블을 건너뛰도록 작성되어 있다. 새 프로젝트에는 이 분기를 적용하지 않는다.

두 경우 모두 스키마·RLS·마이그레이션이 현재 코드와 맞는지 별도로 확인하고, 배포 전 [Supabase Production Checklist](https://supabase.com/docs/guides/deployment/going-into-prod)도 확인한다.

Cloud Run에는 아래 **이름의 비밀**을 Secret Manager에 저장하고, 각 비밀의 최신 버전을 서비스에 연결한다. 이름만 적었으며 값은 이 문서에 기록하지 않는다.

| Secret Manager 비밀 이름 | Cloud Run 환경변수 이름 | 필수 여부 |
| --- | --- | --- |
| `coordit-staging-supabase-url` | `SUPABASE_URL` | 필수 |
| `coordit-staging-supabase-anon-key` | `SUPABASE_ANON_KEY` | 필수 |
| `coordit-staging-supabase-service-role-key` | `SUPABASE_SERVICE_ROLE_KEY` | 필수 |
| `coordit-staging-anthropic-api-key` | `ANTHROPIC_API_KEY` | 선택 |
| `coordit-staging-openrouter-api-key` | `OPENROUTER_API_KEY` | 선택 |

Secret Manager에서 비밀을 만든 뒤, 아래에서 만든 런타임 서비스 계정에 각 비밀의 **Secret Manager Secret Accessor** 권한을 부여한다. 콘솔에서는 Secret Manager → 비밀 선택 → Permissions에서 설정한다. 이 권한이 없으면 서비스가 시작하지 못한다.

### 런타임 서비스 계정(최소 권한)

Cloud Run에는 배포자 계정과 별도의 전용 런타임 서비스 계정을 사용한다. 이 계정에는 프로젝트 소유자·편집자·Artifact Registry 관리자 권한을 주지 말고, 위 표의 비밀을 읽는 권한만 비밀별로 부여한다. 아래 명령의 꺾쇠괄호 값만 식별자로 바꾼다(비밀값을 넣는 명령이 아니다).

```bash
export RUNTIME_SA_NAME=coordit-staging-runtime
export RUNTIME_SA_EMAIL="${RUNTIME_SA_NAME}@<GCP_PROJECT_ID>.iam.gserviceaccount.com"

gcloud iam service-accounts create "${RUNTIME_SA_NAME}" \
  --project <GCP_PROJECT_ID> \
  --display-name="Coordit staging Cloud Run runtime"

for SECRET_NAME in \
  coordit-staging-supabase-url \
  coordit-staging-supabase-anon-key \
  coordit-staging-supabase-service-role-key; do
  gcloud secrets add-iam-policy-binding "${SECRET_NAME}" \
    --project <GCP_PROJECT_ID> \
    --member="serviceAccount:${RUNTIME_SA_EMAIL}" \
    --role="roles/secretmanager.secretAccessor"
done
```

AI 비밀을 연결할 때는 같은 명령을 해당 비밀 이름에 반복한다. 예를 들어 `coordit-staging-anthropic-api-key`에만 같은 Secret Accessor 역할을 추가한다. 배포를 실행하는 사람에게는 이 서비스 계정으로 동작할 수 있는 `roles/iam.serviceAccountUser` 권한이 필요할 수 있다. 이 권한은 배포자에게만 부여하고 런타임 서비스 계정 자체에는 부여하지 않는다.

비밀이 아닌 일반 환경변수는 다음 이름으로 설정한다. `NODE_ENV`는 `production`으로 설정하고, `CORS_ORIGINS`는 **필수**다. `CORS_ORIGINS`에는 스테이징 웹 앱의 정확한 HTTPS origin만 쉼표로 구분해 넣는다(경로·마지막 `/` 제외). 아직 웹 스테이징 origin을 정하지 못했다면 배포 전에 정한다. 나머지는 현재 코드의 기본값을 써도 되어 처음에는 생략할 수 있다: `OPENROUTER_MODEL`, `OPENROUTER_TIMEOUT_MS`, `CRAWL_TIMEOUT_MS`, `PAGE_LOAD_TIMEOUT_MS`, `MAX_CONCURRENT_PAGES`, `MAX_REDIRECTS`, `MAX_JSON_RESPONSE_BYTES`, `MAX_HTML_BYTES`, `MAX_IMAGES`, `DOMAIN_REQUEST_DELAY_MS`, `USER_RATE_LIMIT_PER_MINUTE`, `USER_AGENT`.

## 4. Docker를 로컬에서 먼저 확인

Cloud에 올리기 전, 저장소 최상위에서 이미지를 만든다. 이 단계는 실제 비밀이나 클라우드 인증 없이 가능하다.

```bash
docker build -f backend/Dockerfile -t coordit-backend-staging:local backend
docker image inspect coordit-backend-staging:local --format '{{.Id}}'
```

두 번째 명령이 이미지 ID를 출력하면 빌드는 성공이다. `/health`까지 확인하려면 Git에서 추적하지 않는 개인 환경 파일을 준비하고(파일명·값을 문서, 채팅, 커밋에 쓰지 않음), 그 파일만 컨테이너에 전달한다.

```bash
docker run --rm --env-file <LOCAL_SECRET_ENV_FILE> -e NODE_ENV=development -e CORS_ORIGINS=http://localhost:3000 -e PORT=8080 -p 8080:8080 coordit-backend-staging:local
```

`NODE_ENV=development`는 Dockerfile의 production 기본값을 로컬 health-check에서만 덮어써 HTTP localhost origin을 허용하는 설정이다. `CORS_ORIGINS=http://localhost:3000`도 로컬 health-check에만 쓰는 비밀이 아닌 설정이다. Cloud Run에서는 이 override를 사용하지 말고 `NODE_ENV=production`과 스테이징 웹 앱의 정확한 HTTPS origin을 설정한다.

다른 터미널에서 다음을 실행한다.

```bash
curl --fail --silent --show-error http://127.0.0.1:8080/health
```

성공 기준은 HTTP 200과 `ok` 및 `service` 필드가 있는 JSON이다. 확인 후 첫 터미널에서 `Ctrl+C`로 컨테이너를 종료한다. 실제 비밀이 없으면 첫 두 명령까지만 실행하고, 헬스체크는 Secret Manager 연결 후 Cloud Run에서 수행한다. URL 가져오기는 Playwright/Chromium을 사용하므로 Dockerfile은 [Playwright Docker 공식 안내](https://playwright.dev/docs/docker)의 브라우저 버전과 시스템 의존성 주의사항을 따라야 한다.

## 5. Artifact Registry에 이미지 올리기

Artifact Registry는 Docker 이미지를 보관하는 Google Cloud 저장소다. 한 번만 저장소를 만들고, 배포마다 서로 다른 태그를 사용한다. 아래의 `<...>`는 실제 식별자로 교체한다. 예시는 비밀값을 포함하지 않는다.

```bash
gcloud artifacts repositories create coordit-staging \
  --repository-format=docker \
  --location=asia-northeast3 \
  --description="Coordit staging backend images"

gcloud auth configure-docker asia-northeast3-docker.pkg.dev

docker tag coordit-backend-staging:local \
  asia-northeast3-docker.pkg.dev/<GCP_PROJECT_ID>/coordit-staging/coordit-backend:<IMMUTABLE_TAG>

docker push \
  asia-northeast3-docker.pkg.dev/<GCP_PROJECT_ID>/coordit-staging/coordit-backend:<IMMUTABLE_TAG>
```

`<IMMUTABLE_TAG>`에는 Git 커밋 SHA처럼 다시 바뀌지 않는 식별자를 쓴다. `latest`만 사용하면 어떤 이미지로 되돌렸는지 알기 어렵다. 저장소가 이미 있으면 `repositories create`는 건너뛴다.

## 6. Cloud Run 스테이징 API 만들기

### CLI 경로

아래 명령은 공개 스테이징 API를 만든다. 공개 접근이 조직 정책상 허용되지 않으면 `--allow-unauthenticated`를 빼고, 앱이 호출할 인증 방식(IAM 또는 API Gateway)을 먼저 설계한다. 이미지 태그와 프로젝트 ID만 바꾸고 비밀값은 추가하지 않는다.

```bash
gcloud run deploy coordit-backend-staging \
  --image asia-northeast3-docker.pkg.dev/<GCP_PROJECT_ID>/coordit-staging/coordit-backend:<IMMUTABLE_TAG> \
  --service-account coordit-staging-runtime@<GCP_PROJECT_ID>.iam.gserviceaccount.com \
  --region asia-northeast3 \
  --port 8080 \
  --memory 1Gi \
  --concurrency 1 \
  --min-instances 0 \
  --max-instances 2 \
  --allow-unauthenticated \
  --set-env-vars NODE_ENV=production,CORS_ORIGINS=<WEB_STAGING_ORIGIN> \
  --set-secrets SUPABASE_URL=coordit-staging-supabase-url:latest,SUPABASE_ANON_KEY=coordit-staging-supabase-anon-key:latest,SUPABASE_SERVICE_ROLE_KEY=coordit-staging-supabase-service-role-key:latest
```

AI 기능을 스테이징에서 확인할 때만 콘솔의 **Variables & Secrets**에서 선택 비밀 `ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY`를 각각 위 표의 Secret Manager 이름으로 연결한다. 필요하지 않으면 연결하지 않는다.

Cloud Run의 시작(Startup) 헬스체크는 이 API에 아직 별도 설정하지 않는다. 앱 자체 확인 주소는 `/health`이며, 배포 직후 아래 스모크 테스트로 검증한다. 플랫폼 헬스체크 설정을 추가하는 경우 [Cloud Run health checks](https://cloud.google.com/run/docs/configuring/services/healthchecks) 문서의 경로·포트 요구사항에 맞춘다.

### 콘솔에서 같은 설정을 하는 방법

Google Cloud Console → **Cloud Run** → **Deploy container**를 연다.

1. 위에서 푸시한 Artifact Registry 이미지와 태그를 선택한다.
2. 서비스 이름에 `coordit-backend-staging`, 리전에 `asia-northeast3`을 입력한다.
3. Container(s), Volumes, Networking, Security에서 컨테이너 포트 `8080`, 메모리 `1 GiB`, 동시성 `1`, 최소 인스턴스 `0`, 최대 인스턴스 `2`를 입력한다.
4. Variables & Secrets에서 `NODE_ENV=production`과 `CORS_ORIGINS`(스테이징 웹 앱 origin)를 설정하고, 표에 있는 환경변수 이름과 Secret Manager 비밀을 연결한다. 비밀값을 UI나 메모에 복사하지 않는다.
5. 인증은 팀의 공개 API 정책을 확인한 뒤 Allow public access를 선택한다. 선택하면 `/health`와 API URL을 누구나 요청할 수 있으므로 앱 인증과 속도 제한을 별도로 점검한다.
6. **Create**를 누르고 Revision이 Ready 상태가 될 때까지 기다린다.

더 자세한 화면/CLI 옵션은 [Cloud Run 컨테이너 배포 공식 안내](https://cloud.google.com/run/docs/deploying)와 [환경변수·비밀 설정 안내](https://cloud.google.com/run/docs/configuring/services/environment-variables)를 따른다.

## 7. 배포 직후 스모크 테스트와 앱 연결

Cloud Run 서비스 상세 화면에서 URL을 복사하거나 아래처럼 확인한다.

```bash
gcloud run services describe coordit-backend-staging \
  --region asia-northeast3 \
  --format='value(status.url)'

curl --fail --silent --show-error <CLOUD_RUN_SERVICE_URL>/health
```

HTTP 200과 `{"ok":true,"service":"coordit-backend"}`를 받기 전에는 웹 또는 iOS 앱의 API 기본 URL을 바꾸지 않는다. 성공한 뒤 웹의 `NEXT_PUBLIC_API_BASE_URL`과 iOS 설정을 이 Cloud Run URL로 맞춘다. 이 URL은 HTTPS이며 끝에 `/`를 덧붙이지 않는다. 앱 변경 후 로그인과 읽기 전용 API 한 건을 별도로 확인한다.

#### iOS API URL 설정

iOS 앱은 임의의 환경변수나 코드 상수를 편집하지 않고, 다음 두 방법 중 하나로 `CoorditAPIBaseURL`을 설정한다. 저장소의 `coordit/coordit/Info.plist`에는 이 키와 `$(COORDIT_API_BASE_URL)` 토큰이 이미 들어 있으므로, 빌드 설정에서는 토큰을 채울 변수 이름을 정확히 `COORDIT_API_BASE_URL`로 사용한다.

- **빌드 설정/Info.plist(권장)**: Xcode에서 해당 Target의 **Build Settings → User-Defined**에 `COORDIT_API_BASE_URL = https://<CLOUD_RUN_HOST>`를 추가한다. 소스의 Info.plist 항목은 다음과 같다(키 이름과 토큰을 바꾸지 않는다).

  ```xml
  <key>CoorditAPIBaseURL</key>
  <string>$(COORDIT_API_BASE_URL)</string>
  ```

- **실행 인자(개발·수동 테스트)**: Xcode Scheme → Run → Arguments에 `--coordit-api-base-url`와 `https://<CLOUD_RUN_HOST>`를 차례로 추가한다. 앱이 지원하는 정확한 형식은 `--coordit-api-base-url <URL>`이며, 이 인자가 번들 설정값보다 우선한다.

Release 빌드에서는 위 값과 실행 인자 모두 `https://` URL이어야 한다. 앱 코드가 Release에서 HTTP를 거부하므로 `http://localhost:4000`은 Debug 빌드에서만 사용한다. 스테이징 Cloud Run 기본 URL은 HTTPS이므로 Release 테스트에도 그대로 사용할 수 있다.

처음에는 커스텀 도메인(예: `api-staging.example.com`)을 연결하지 않는다. Cloud Run 기본 URL과 `/health`가 안정적으로 확인되고, 앱의 CORS·인증·모니터링 요구사항이 정리된 뒤 별도 변경으로 DNS 소유권 확인 및 도메인 매핑을 진행한다.

## 8. 문제 발생 시 롤백

Cloud Run은 배포마다 revision(변경 이력)을 만든다. 먼저 오류 로그와 `/health` 실패 여부를 확인하고, 마지막으로 정상인 revision 이름을 찾아 100% 트래픽을 되돌린다.

```bash
gcloud run revisions list \
  --service coordit-backend-staging \
  --region asia-northeast3

gcloud run services update-traffic coordit-backend-staging \
  --region asia-northeast3 \
  --to-revisions <LAST_KNOWN_GOOD_REVISION>=100
```

롤백 뒤 반드시 다시 `curl <CLOUD_RUN_SERVICE_URL>/health`를 실행하고, Cloud Run logs에서 새 오류가 멈췄는지 확인한다. 롤백은 데이터베이스 스키마 변경을 되돌리지 않는다. 스키마 변경은 호환 가능한 마이그레이션과 별도 복구 계획을 먼저 준비한다. 상세 절차는 [Cloud Run 트래픽 롤백 안내](https://cloud.google.com/run/docs/rollbacks-roll-forwards-traffic-migration)를 참고한다.

## 이후 공개 전 필수 구조 분리: URL 가져오기 워커

현재 `POST /api/v1/products/import-url/preview`는 API 요청 안에서 Playwright를 동기적으로 실행한다. 이 방식은 짧은 검증에는 가능하지만, 공개 출시 시 느린 쇼핑몰 응답·브라우저 메모리·재시도가 사용자 요청을 오래 점유할 수 있다.

공개 출시 전에는 다음을 **별도 구현 작업**으로 분리한다. 이 문서의 API Cloud Run 서비스에 지금 추가하지 않는다.

1. API는 URL 검증 후 작업 ID를 만들고 Cloud Tasks에 작업을 넣은 뒤 즉시 상태를 반환한다.
2. 비공개 Playwright crawler worker는 별도 Cloud Run 서비스 또는 Cloud Run Job으로 작업을 처리한다. 외부 공개 접근은 허용하지 않고 Cloud Tasks 호출만 검증한다.
3. 작업 상태·재시도·시간 제한·도메인별 속도 제한을 저장하고, 앱은 상태를 조회하거나 알림을 받는다.

이 분리가 끝나면 API와 워커의 메모리·동시성·최대 인스턴스를 독립적으로 튜닝하고, 크롤러에는 특히 접근 제어와 요청 대상 검증을 적용한다. Cloud Run Job의 개념과 설정은 [Cloud Run Jobs 공식 안내](https://cloud.google.com/run/docs/create-jobs)를 참고한다.
