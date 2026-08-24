# Coordit production deployment and monetization handoff

This runbook covers the owner-controlled production setup for FitLab rewarded yarn and Apple consumable purchases. It never contains credentials, signing material, Supabase keys, Apple JWS payloads, account identifiers, or transaction identifiers.

> **Current gate (2026-08-21): CLOSED for monetization release.** The owner explicitly approved GCP project `coordit-dev`, Cloud Run service `coordit-backend-staging`, and Supabase project `coordit-staging` as the production targets despite their names. Target identity is resolved. The database dump has been copied to an owner-controlled local path and its byte size and SHA-256 match the retained Cloud Shell copy. Exact commit `e2ffafe6a43b442620b06c5659877e0d1321628f` is now serving on Cloud Run revision `coordit-backend-staging-e2ffafe6`; the Cloud Run delivery sub-gate is PASS. The Task 7 Supabase reconciliation has not been executed. `styling_looks` and `users.birth_date` remain separate schema blockers, no Coordit app exists in the visible App Store Connect team, and AdMob SSV remains unverified. Keep `ADMOB_REWARDED_ENABLED=false` and `APPLE_IAP_ENABLED=false` until every corresponding gate below has external evidence.

### Current production-target inventory — mutation remains gated

| Provider | Authenticated read-only observable | Production consequence |
| --- | --- | --- |
| Google Cloud | Owner approved `coordit-dev` / `coordit-backend-staging` in `asia-northeast3`; exact release revision `coordit-backend-staging-e2ffafe6` serves 100% of traffic and retained rollback revision `coordit-backend-staging-00012-rhp` is Ready | Cloud Run delivery is PASS; retain the explicit naming variance and immutable release receipt below |
| Supabase | Owner approved `coordit-staging`; the FREE project reports no managed backup. Direct failed on its IPv6 route, so the displayed Session pooler was used after `SESSION_POOLER_TCP_OK`. The retained Cloud Shell dump and owner-controlled local copy are both 308,567 bytes and have matching SHA-256. Read-only metadata inspection found the accepted partial monetization fingerprint and no Supabase CLI ledger. The public Supabase CA is checksum-pinned in a non-repository operator path, but the exact Node connection-only TLS probe has not yet passed | backup and CA-identity gates are PASS; do not apply the reconciliation until the authenticated TLS connection-only gate also passes |
| App Store Connect | No Coordit app is present; updated agreement and legal/compliance prerequisites block the Paid Apps Agreement | Account Holder/legal handoff and correct team/app identity are required before IAP work |
| AdMob | `Coordit iOS` is review-required; rewarded unit/reward values match, but SSV points to staging with blank validation custom data and disabled **Use verified URL** | do not Verify, Use, or Save until a healthy production callback and zero-grant sentinel are ready |

The initial provider receipt is `.omo/evidence/coordit-release-monetization/task-7/red/profile1-authenticated-discovery.md`; the explicit target variance and fresh preflight are in `.omo/evidence/coordit-release-monetization/task-7/red/approved-target-preflight.md`. No provider settings were changed during either inspection.

## 1. Fixed application contract

These public identifiers are fixed by the release candidate and must match provider configuration exactly.

| Surface | Required value |
| --- | --- |
| iOS bundle identifier | `com.inseong.coordit` |
| AdMob app identifier | `ca-app-pub-7471774017488090~7708433733` |
| AdMob rewarded unit | `ca-app-pub-7471774017488090/3769188728` |
| AdMob reward | item `실타래`, amount `1` |
| AdMob SSV path | `/webhooks/admob/rewarded` |
| AdMob signed validation custom data | `coordit-admob-ssv-validation-v1` |
| Apple notifications V2 path | `/webhooks/apple/app-store-notifications` |
| Pack 5 | consumable `com.inseong.coordit.thread.5`, server credit `5` |
| Pack 10 | consumable `com.inseong.coordit.thread.10`, server credit `10` |
| Pack 20 | consumable `com.inseong.coordit.thread.20`, server credit `20` |

`coordit/coorditUITests/CoorditThreadProducts.storekit` contains local test prices of KRW 1,500 / 2,500 / 4,000. Those are test fixture values, not authority to choose production prices. The owner must confirm the exact App Store price point, base storefront, tax category, availability, and metadata before any product is created or edited.

## 2. Owner preflight: identify the exact targets first

Do not run any mutating command until one change record contains all of the following non-secret fields:

- approved Git commit SHA and immutable container image digest;
- production GCP project name/ID, Cloud Run service name, region, runtime service-account name, and approved HTTPS host;
- production Supabase project name/reference, including the owner's explicit naming variance where applicable, plus backup/PITR checkpoint time;
- App Store Connect app name, bundle ID, numerical Apple app ID, and authorized operator role;
- approved product price points and metadata for all three immutable product IDs;
- production and sandbox Notifications V2 HTTPS destinations;
- AdMob app and rewarded unit IDs from section 1;
- change owner, approver, start time, rollback revision, and completion result.

Record names, public hosts, booleans, timestamps, and revision IDs only. Never paste account emails, access tokens, service-role keys, database passwords, Apple signed payloads, certificates, or Secret Manager values into the record.

The normal policy is to keep production targets distinct from staging. For this release, the owner explicitly approved the existing staging-named resources as production; that variance must remain in the change record. The active Release project, Cloud Run service, and AdMob callbacks use `https://coordit-backend-staging-789827940031.asia-northeast3.run.app`.

The earlier `curl --fail` receipt for the former Release alias and the Cloud Run console host remains historical evidence only. Use the active public host above for provider callbacks; do not treat the former alias as an active release target.

## 3. Supabase production reconciliation gate

The production database is not an empty database and must not be treated as one. Read-only Task 7 inspection found this accepted partial fingerprint:

- `supabase_migrations.schema_migrations` is absent;
- the wallet and AdMob monetary tables already exist with RLS, the wallet reason constraint already includes `fit_report` and `ad_reward`, and the three-column wallet idempotency rule is present;
- the deployed `grant_admob_reward` function is the older, non-hardened form;
- the Apple transaction and notification tables/functions are absent;
- `styling_looks` and `users.birth_date` are absent.

Do **not** replay the historical migration directory, run `supabase db push`, feed the reconciliation SQL directly to `psql`, or paste it into the Supabase SQL dashboard. The history has no durable CLI ledger and includes a duplicated timestamp prefix; replaying it would be an unverified rewrite of a partially reconciled database. Direct execution is also intentionally rejected when the typed runner context is absent.

### Immutable reconciliation artifact

The only approved monetization schema operation is this single forward artifact:

| Field | Required value |
| --- | --- |
| Migration | `supabase/migrations/20260822_reconcile_monetization_release_schema.sql` |
| SHA-256 | `3cc70e8ddc56e4ca9a923bb368f144d84afe680a3bcddc7bae37e23595dc9233` |
| Typed runner | `backend/src/modules/thread-wallet/monetization-schema-reconciliation.runner.ts` |
| Operator CLI | `backend/src/modules/thread-wallet/monetization-schema-reconciliation.runner.cli.ts` |
| Package command | `npm --prefix backend run apply:monetization-schema-reconciliation` |

Execute only from a reviewed, checked-in release candidate containing those exact paths. Immediately before the change, recompute both the checked-out and committed migration checksums and stop unless both match the table. A working-tree-only match is not an approved release candidate. The current Cloud Run receipt in section 4 remains exact and unchanged; it does not prove that a later database-operator candidate was reviewed or checked in.

```bash
expected_reconciliation_sha='3cc70e8ddc56e4ca9a923bb368f144d84afe680a3bcddc7bae37e23595dc9233'
migration_path='supabase/migrations/20260822_reconcile_monetization_release_schema.sql'
reviewed_commit="$(git rev-parse --verify HEAD)"
checked_out_sha="$(sha256sum "$migration_path" | awk '{print $1}')"
committed_sha="$(git show "$reviewed_commit:$migration_path" | sha256sum | awk '{print $1}')"
test "$checked_out_sha" = "$expected_reconciliation_sha"
test "$committed_sha" = "$expected_reconciliation_sha"
test -z "$(git status --porcelain --untracked-files=no)"
printf 'active_reconciliation_identity=pass commit=%s\n' "$reviewed_commit"
```

### Secure operator TLS is mandatory

Use only the public server CA downloaded from the authenticated `coordit-staging` Supabase dashboard at **Database Settings → SSL Configuration → Download certificate**. This download does not change a provider setting.

| Field | Required value |
| --- | --- |
| Provider filename | `prod-ca-2021.crt` |
| Byte size | `1,367` |
| SHA-256 | `700723581420dd1ac98fd7e9ac529f0ef210eadcaf87fc868a3ad7d114c2f3b7` |
| Operator path | `$HOME/coordit-task7-supabase-root-ca.crt` |
| File policy | regular file, mode `0600`, outside every repository, never committed |

Recompute the size and SHA-256 and parse the file with `openssl x509 -noout` before every operator session. Set `PGSSLROOTCERT` to the exact operator path. `PGSSLMODE=require` by itself is not acceptable because it does not establish the pinned authenticated-TLS gate. `sslmode=disable`, `NODE_TLS_REJECT_UNAUTHORIZED=0`, `rejectUnauthorized: false`, or any equivalent certificate/hostname-verification bypass is forbidden. The checked-in operator client must load `PGSSLROOTCERT` and construct Node `pg` with the pinned CA and `rejectUnauthorized: true`; missing, malformed, non-CA, or unreadable input must fail before a TCP connection.

Before any apply command, run the exact checked-in connection-only package command from the same reviewed checkout and with the same Session-pooler `PG*` environment. It uses the same verified operator client as the apply runner, performs only `connect()` followed by `end()`, issues no query, and must print exactly `monetization_connection_probe status=connected`. Any nonzero exit or any other output closes the database gate. Do not set the reconciliation approval token until this probe succeeds.

### Required preflight and invocation

1. Reconfirm `coordit-staging` in the authenticated owner console and record the approved staging-name variance, operator, time window, reviewed Git commit, and rollback owner.
2. Recheck both retained dump copies. The Cloud Shell and owner-controlled local copy must each remain 308,567 bytes with SHA-256 `e27ae11df6662b3786df76e575699b1b11ae28cc500258d2bc31f88eb9eb0333`. Stop on any size or digest mismatch.
3. Run all five checked-in suites below: the partial/exact-target reconciliation scenario, fingerprint rejection scenarios, transaction-failure rollback scenarios, operator TLS fail-closed coverage, and the exact connection-probe contract. Stop unless each exits 0.
4. Keep `ADMOB_REWARDED_ENABLED` and `APPLE_IAP_ENABLED` absent or false. Do not add the Apple certificate mount as part of this database change.
5. Use the IPv4-compatible **Session pooler** target shown by Supabase Connect. Do not use the failed Direct IPv6 target or the Transaction pooler. Supply its host, port, user, and database only through standard `PG*` variables and enter the password at a masked prompt; never put a connection URI or password in shell history, logs, evidence, or this runbook.
6. Verify the public CA's exact size, SHA-256, mode, and certificate parse; export its exact non-repository path as `PGSSLROOTCERT` and run only the checked-in connection-only probe. Stop unless it exits 0 with the single allowlisted success line.
7. Only after the probe passes, set the public, exact approval token for the apply invocation: `coordit-monetization-schema-reconciliation-20260822`.

```bash
npm --prefix backend run test:monetization-schema-reconciliation
npm --prefix backend run test:monetization-schema-reconciliation:fingerprint
npm --prefix backend run test:monetization-schema-reconciliation:failures
npm --prefix backend run test:monetization-schema-reconciliation:operator-tls
npm --prefix backend run test:monetization-schema-reconciliation:connection-probe
```

From the root of the exact reviewed checkout, the owner-controlled Cloud Shell invocation has this shape:

```bash
(
  set -eu
  read -r -s -p "Supabase Session pooler password: " PGPASSWORD
  printf '\n'
  trap 'unset PGPASSWORD PGSSLROOTCERT COORDIT_SCHEMA_RECONCILIATION_APPROVAL' EXIT
  export PGPASSWORD
  export PGHOST='<CONFIRMED_SESSION_POOLER_HOST>'
  export PGPORT='<CONFIRMED_SESSION_POOLER_PORT>'
  export PGUSER='<CONFIRMED_SESSION_POOLER_USER>'
  export PGDATABASE='<CONFIRMED_DATABASE_NAME>'
  export PGSSLMODE='verify-full'
  export PGSSLROOTCERT="$HOME/coordit-task7-supabase-root-ca.crt"
  export PGCONNECT_TIMEOUT='10'
  npm --prefix backend run --silent probe:monetization-schema-reconciliation:connection
  export COORDIT_SCHEMA_RECONCILIATION_APPROVAL='coordit-monetization-schema-reconciliation-20260822'
  npm --prefix backend run apply:monetization-schema-reconciliation
)
```

The probe is not a schema preflight and its success does not authorize an apply; it proves only that the exact Node operator client can complete authenticated TLS and immediately disconnect without a query. The apply CLI computes the checked-in SQL checksum itself. It opens one transaction, applies five-second lock and 30-second statement timeouts, takes a fixed advisory transaction lock, validates the catalog fingerprint, runs the single forward reconciliation, and performs its fixed metadata postflight before commit. Missing approval, operator CA, checksum/version conflict, unexpected Supabase ledger, unknown catalog drift, lock/statement timeout, or postflight failure must exit nonzero and roll back the transaction.

### Expected fingerprint and durable receipt

For the observed production partial fingerprint, a successful first run must return:

- `status=committed`;
- the exact filename and SHA-256 above;
- `disposition=reconciled_observed_partial`;
- `connection=redacted`.

It atomically preserves wallet rows, installs the missing Apple monetary schema, hardens AdMob reward atomicity, creates the RLS-protected `coordit_schema_change_records` and `coordit_monetization_schema_versions` tables, and writes one durable change record for version `20260822`. The marker table must contain exactly the five expected component/version pairs for wallet, AdMob reward, Apple IAP, Apple notifications, and release reconciliation. A replay against that reconciled fingerprint is idempotent and preserves the original filename, SHA, disposition, markers, and wallet state. A database already at the exact target without a conflicting record may report `verified_exact_target`; any unrecognized partial state or same-version/different-SHA record is a hard failure before commit.

The runner's transaction-local postflight is the authoritative schema check: it verifies both receipt tables, Apple monetary tables, the hardened AdMob function marker, the exact filename/SHA change record, and all five version markers without selecting user rows. Preserve only the redacted CLI receipt and exit status. After commit, recheck both public `/health` URLs and the authenticated monetization readiness endpoint; health must remain HTTP 200 and both readiness values must remain false. Do not enable either feature flag in this change window.

On any runner failure, retain the verified dump, record the redacted error category, and investigate the fingerprint; do not retry with hand-edited SQL. The runner rolls back its transaction. After a successful commit, do not run reverse SQL or drop ledger/receipt rows. Use a separately reviewed forward reconciliation for correction; restore the verified dump only under an owner-approved database recovery incident. The Cloud Run rollback revision remains `coordit-backend-staging-00012-rhp`, but database reconciliation alone does not move application traffic.

After the operator receipt and postflight evidence are captured and no retry is pending, remove only the exact task-owned public CA copy and confirm it is absent:

```bash
rm -- "$HOME/coordit-task7-supabase-root-ca.crt"
test ! -e "$HOME/coordit-task7-supabase-root-ca.crt"
```

Also unset any remaining `PG*` operator variables. Do not leave the CA in a repository, source archive, container image, shell evidence bundle, or long-lived runtime configuration.

`styling_looks` and `users.birth_date` are intentionally untouched by this monetization reconciliation and remain separate schema blockers requiring their own reviewed forward changes. App Store Connect app/product/agreement/notification/certificate work and the AdMob verified-URL/live-reward gates also remain separate blockers; this database receipt cannot turn either CTA on.

### Separate profile/styling forward repair

Do not replay `20260511_add_styling_looks.sql`, `20260813_add_user_birth_date.sql`, the historical migration directory, or `supabase db push`. After independently confirming the exact committed `20260822` monetary receipt above, the only reviewed profile/styling repair artifact is:

| Field | Required value |
| --- | --- |
| Migration | `supabase/migrations/20260824_reconcile_profile_styling_schema.sql` |
| SHA-256 | `3d2bd3c10d6688d5f5fa6d1ccc010aa3a932478b16536bc68a41d4c50b116c17` |
| Typed runner | `backend/src/modules/styling/profile-styling-schema-reconciliation.runner.ts` |
| Operator CLI | `backend/src/modules/styling/profile-styling-schema-reconciliation.runner.cli.ts` |
| Approval token | `coordit-profile-styling-schema-reconciliation-20260824` |

Use a separate reviewed change window and the same backup, Session-pooler, verified-CA, clean-commit, and secret-handling gates described above. Run all checked-in local gates before the connection probe:

```bash
npm --prefix backend run typecheck
npm --prefix backend run test:profile-styling-schema-reconciliation
npm --prefix backend run test:profile-styling-schema-reconciliation:fingerprint
npm --prefix backend run test:profile-styling-schema-reconciliation:failures
npm --prefix backend run test:profile-styling-schema-reconciliation:operator
npm --prefix backend run test:profile-styling-schema-reconciliation:connection-probe
```

With the same standard `PG*` variables and `PGSSLROOTCERT` set for the approved Session pooler, run the scope-specific connection-only probe first. It performs `connect()` and `end()` only and must print exactly `profile_styling_connection_probe status=connected`. Set the distinct approval variable only after that succeeds:

```bash
npm --prefix backend run --silent probe:profile-styling-schema-reconciliation:connection
export COORDIT_PROFILE_STYLING_SCHEMA_RECONCILIATION_APPROVAL='coordit-profile-styling-schema-reconciliation-20260824'
npm --prefix backend run apply:profile-styling-schema-reconciliation
```

The runner accepts only the paired-absent observed state or the fully exact paired target. It rejects a Supabase migration ledger, a missing or mismatched `20260822` monetary receipt, one-sided state, wrong columns/defaults/FK/index/security, or a conflicting `20260824` record before commit. One transaction sets five-second lock and 30-second statement timeouts, takes a fixed advisory transaction lock, records the migration filename/SHA, runs a fixed read-only postflight, and rolls back on any failure.

The observed partial success receipt must report `status=committed`, the filename and SHA above, `disposition=reconciled_observed_partial`, and `connection=redacted`. The only schema additions are nullable `public.users.birth_date date`, the exact `public.styling_looks` table plus owner index, and one `20260824` row in the existing change-record table. `styling_looks` has RLS enabled with no policies, no `anon`/`authenticated` privileges, and service-role CRUD only because current backend persistence uses the service client. Replay preserves the original receipt. Never reverse a committed repair; use another reviewed forward migration. Remove the task-owned CA copy and unset operator variables after the redacted receipt is retained.

Supabase's current production guidance recommends distinct environments, version-controlled migrations, RLS review, backups/PITR, and restricted production access: <https://supabase.com/docs/guides/deployment/going-into-prod>.

## 4. Cloud Run production service

Deploy only to the existing owner-approved `coordit-backend-staging` service in `coordit-dev`; its staging-style name is an explicit release variance, not permission to create or substitute another service. Build from the exact approved release-candidate commit and use an immutable image digest or commit-derived immutable tag; do not deploy `latest`. Start with both monetization flags false.

### Current immutable release receipt — Cloud Run sub-gate PASS

| Field | Verified value |
| --- | --- |
| Exact source commit | `e2ffafe6a43b442620b06c5659877e0d1321628f` |
| Source archive | 190,235 bytes; SHA-256 `306a8d4f25d585a0b5d34bd52efb4f160af5901b5f10c91f8f74d6aabd740d13` |
| Cloud Build | `7a722a5b-4f3b-4fc3-ab65-6f5b50c72392`, `SUCCESS` |
| Immutable image digest | `sha256:0fc8211f4e7cc503880ddd5665d2380a9a4c20bc4a85c8b9ee531f015dad8e01` |
| Serving revision | `coordit-backend-staging-e2ffafe6`, 100% traffic |
| Validation tag | `rc-e2ffafe6` |
| Retained rollback | `coordit-backend-staging-00012-rhp`, Ready |

The local and Cloud Shell source archives matched by byte size and SHA-256 before extraction. The no-traffic revision was Ready on the exact digest, its complete runtime spec matched the previous revision after removing only the image field, and the tagged `/health` endpoint returned HTTP 200 with TLS verification result 0 before traffic moved. After cutover, both the provider callback host and Release alias returned HTTP 200 with `{"ok":true,"service":"coordit-backend"}`; the release revision had zero severity-`ERROR` log entries in the checked window. `ADMOB_REWARDED_ENABLED` and `APPLE_IAP_ENABLED` remain absent, and no Apple certificate volume is mounted. The full no-secret receipt is `.omo/evidence/coordit-release-monetization/task-7/red/cloud-run-release-deployment.md`.

This receipt proves only the Cloud Run delivery sub-gate. It does not authorize Supabase migration, AdMob SSV activation, Apple product creation, certificate mounting, or either monetization feature flag.

### Non-secret runtime configuration

| Variable | Initial production setting |
| --- | --- |
| `NODE_ENV` | `production` |
| `CORS_ORIGINS` | exact owner-approved production HTTPS origins only |
| `APPLE_IAP_BUNDLE_ID` | `com.inseong.coordit` |
| `APPLE_IAP_APPLE_ID` | owner-confirmed positive numerical Apple app ID |
| `APPLE_IAP_ROOT_CERTIFICATE_PATHS` | comma-separated mounted file paths under `/secrets/apple/` |
| `APPLE_IAP_ENABLED` | `false` initially |
| `ADMOB_REWARDED_AD_UNIT_ID` | `ca-app-pub-7471774017488090/3769188728` |
| `ADMOB_REWARD_ITEM` | `실타래` |
| `ADMOB_REWARD_AMOUNT` | `1` |
| `ADMOB_SSV_VALIDATION_CUSTOM_DATA` | `coordit-admob-ssv-validation-v1` |
| `ADMOB_REWARDED_ENABLED` | `false` initially |

Connect `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `JWT_SECRET`, and any optional AI provider keys by Secret Manager reference. Never store their values in a command transcript, environment example, GitHub variable visible to untrusted jobs, or this document.

### Apple root certificates

Store each required Apple root certificate as its own Secret Manager secret. Mount each version as a separate file under a dedicated directory such as `/secrets/apple/root-1.cer`; do not inject certificate bytes as environment-variable literals. Grant only the production runtime service account `roles/secretmanager.secretAccessor` on the exact secrets.

Cloud Run supports file mounts with an update shaped like:

```bash
gcloud run deploy <CONFIRMED_PRODUCTION_SERVICE> \
  --project <CONFIRMED_PRODUCTION_GCP_PROJECT> \
  --region <CONFIRMED_PRODUCTION_REGION> \
  --image <IMMUTABLE_IMAGE_URL> \
  --update-secrets=/secrets/apple/root-1.cer=<CONFIRMED_APPLE_ROOT_SECRET_1>:<PINNED_VERSION>,/secrets/apple/root-2.cer=<CONFIRMED_APPLE_ROOT_SECRET_2>:<PINNED_VERSION>
```

The placeholders are intentionally non-executable until the owner confirms the target. Google documents that a mounted secret becomes a file and that a service configuration change creates a new revision: <https://cloud.google.com/run/docs/configuring/services/secrets>.

Before enabling IAP, verify the files are readable regular files inside the deployed revision and that the authenticated readiness endpoint still reports `iapEnabled: false` while the flag is false. Then set the Apple numerical app ID and root paths, deploy a new revision, and confirm the verifier starts without exposing certificate contents.

### Initial health and fail-closed verification

Only after the production host is confirmed, run:

```bash
curl --fail --silent --show-error https://<CONFIRMED_PRODUCTION_API_HOST>/health
```

PASS is exit 0, HTTP 200, and `{"ok":true,"service":"coordit-backend"}`. With an authorized QA access token, call `GET /thread-wallet/monetization-readiness`; both values must initially be false. Do not record the token.

If the certificate mount is missing, unreadable, or not a regular file, IAP readiness must stay false. If the AdMob flag is false, rewarded readiness must stay false. A crash or a true CTA is a failed deployment.

## 5. Xcode configuration separation

`Info.plist` already resolves `CoorditAPIBaseURL` from `$(COORDIT_API_BASE_URL)`. Release currently embeds the public alias of the owner-approved Cloud Run service and that alias returns the required health payload. Do not ship Release with localhost or any host outside the explicit owner variance.

After updating the project configuration and before archiving, run:

```bash
xcodebuild -showBuildSettings \
  -project coordit/coordit.xcodeproj \
  -scheme coordit \
  -configuration Release \
  | rg 'COORDIT_API_BASE_URL|PRODUCT_BUNDLE_IDENTIFIER'
```

PASS requires exit 0, `PRODUCT_BUNDLE_IDENTIFIER = com.inseong.coordit`, and exactly the confirmed production HTTPS base URL. Preserve redacted output containing the public host and bundle ID only.

## 6. App Store Connect

Do this only in the owner-confirmed Coordit app. The operator needs an appropriate App Store Connect role. The Account Holder must have the Paid Apps Agreement active and banking/tax setup complete before paid products are usable.

1. Confirm bundle ID `com.inseong.coordit` and record the app's numerical Apple ID as a non-secret runtime value.
2. Under Monetization → In-App Purchases, verify or create exactly three **Consumable** products with the IDs in section 1. Product IDs are immutable; stop on any mismatch instead of creating a near-match.
3. Apply only owner-approved price points. The local StoreKit fixture prices are test data until the owner explicitly approves them.
4. Complete Korean display name/description, review notes and screenshots, tax category, storefront availability, and submission status for each product.
5. Confirm Paid Apps Agreement is **Active**, with tax and banking complete. Never capture bank or tax details in evidence.
6. Under App Information → App Store Server Notifications, configure Version 2 for both environments:
   - production: `https://<CONFIRMED_PRODUCTION_API_HOST>/webhooks/apple/app-store-notifications`;
   - sandbox: `https://<CONFIRMED_STAGING_OR_SANDBOX_API_HOST>/webhooks/apple/app-store-notifications`.
7. Request an Apple test notification and retrieve its status. PASS is accepted 2xx delivery to the intended revision. Record only timestamps, environment, HTTP class, and a hash/correlation label—never the token or signed payload.

Apple's owner workflow and role requirements are documented at:

- <https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/>
- <https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase/>
- <https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications>
- <https://developer.apple.com/documentation/appstoreservernotifications/enabling-app-store-server-notifications>

Keep `APPLE_IAP_ENABLED=false` until all product, agreement, certificate, notification, and Sandbox/TestFlight purchase gates pass. Enabling the flag is a separate revision and must be followed by authenticated readiness verification before the IAP CTA may be enabled.

## 7. AdMob SSV

The current known RED is an HTTP 400 during URL verification, with **Use verified URL** disabled. Do not save that configuration as if it were verified.

After the production callback is healthy and the production service has the exact public AdMob values from section 1:

1. Keep `ADMOB_REWARDED_ENABLED=false` while validating the endpoint contract and zero-grant sentinel locally/staging.
2. In AdMob, open Coordit's rewarded unit `ca-app-pub-7471774017488090/3769188728` → Advanced settings → Server-side verification.
3. Enter `https://<CONFIRMED_PRODUCTION_API_HOST>/webhooks/admob/rewarded`.
4. Enter signed test custom data `coordit-admob-ssv-validation-v1`. Do not use a real user or reward-attempt ID for the URL check.
5. Click **Verify URL** once. PASS requires a successful verification and zero wallet/ledger grant.
6. Only after PASS, click **Use verified URL**, enable **Apply to all networks in mediation groups** where required, and Save.
7. Capture a redacted screenshot showing the public URL and verified state, with account identity and notifications hidden.
8. Deploy a separate revision with `ADMOB_REWARDED_ENABLED=true`, verify authenticated readiness, then execute the real test-device gate. Do not enable Apple IAP as part of this revision unless its independent gate is already green.

Google's current UI sequence requires Verify URL before Use verified URL and Save: <https://support.google.com/admob/answer/9603226?hl=en>.

## 8. Binary release gate

Every row must be PASS before release. A failed row keeps only its associated CTA disabled.

| Gate | PASS observable | On failure |
| --- | --- | --- |
| Production identity | exact GCP service and Supabase project confirmed in authenticated owner consoles and owner variance recorded | stop; do not deploy or migrate |
| Database recovery | backup/PITR checkpoint and rollback owner recorded | stop migration |
| Monetization reconciliation | exact `20260822_reconcile_monetization_release_schema.sql` SHA recorded once, five component/version markers present, and fixed runner postflight committed | keep both flags false; do not paste or replay SQL |
| Cloud Run health | confirmed production `/health` is HTTP 200 | roll back traffic; keep flags false |
| Secret mounts | each Apple path is a readable regular file; no secret literal in config | keep IAP false |
| Initial readiness | authenticated response is ads false / IAP false | reject revision |
| Release URL | Release embeds only confirmed production HTTPS host | reject archive |
| AdMob URL | verified UI state saved; sentinel produces zero grant | keep rewarded ads false |
| AdMob live test | one test ad produces exactly one server ledger credit | keep rewarded ads false |
| IAP products | exact three IDs, approved price/metadata, available for testing | keep IAP false |
| Apple business | Paid Apps Agreement active; tax/banking complete | keep IAP false |
| Apple notifications | V2 production+sandbox URLs saved; test notification accepted 2xx and deduped | keep IAP false |
| Apple Sandbox purchase | one authorized purchase credits once; replay is already credited | keep IAP false |

## 9. Rollback and evidence hygiene

- Roll back Cloud Run traffic to the recorded last-known-good revision. Do not delete the production service or database.
- If monetization misbehaves, deploy a revision with the affected feature flag false and verify readiness before investigating.
- Never reverse an applied production migration. Add a forward-compatible migration after review.
- Preserve ledger audit rows. Remove only sanctioned sandbox/test data through provider tools.
- Evidence may contain public URLs, product/ad IDs, revision names, timestamps, booleans, counts, status codes, and hashes. It must not contain tokens, signed payloads, raw transaction IDs, account emails, bank/tax data, database rows, certificates, or secret values.
