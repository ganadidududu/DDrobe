# Coordit production deployment and monetization handoff

This runbook covers the owner-controlled production setup for FitLab rewarded yarn and Apple consumable purchases. It never contains credentials, signing material, Supabase keys, Apple JWS payloads, account identifiers, or transaction identifiers.

> **Current gate (2026-08-21): CLOSED.** The owner explicitly approved GCP project `coordit-dev`, Cloud Run service `coordit-backend-staging`, and Supabase project `coordit-staging` as the production targets despite their names. Target identity is resolved. A non-empty logical dump now exists in the authorized Cloud Shell, but its secure local copy is not yet downloaded and checksum-verified. Immutable local release-candidate commits now exist, but they have not been pushed or deployed. No deployment or migration may begin until the local backup checksum is verified and the exact candidate commit/image is entered in the change record. No Coordit app exists in the visible App Store Connect team, and AdMob SSV is still unverified. Keep `ADMOB_REWARDED_ENABLED=false` and `APPLE_IAP_ENABLED=false` until every corresponding gate below has external evidence.

### Current production-target inventory — mutation remains gated

| Provider | Authenticated read-only observable | Production consequence |
| --- | --- | --- |
| Google Cloud | Owner approved `coordit-dev` / `coordit-backend-staging` in `asia-northeast3`; current revision `coordit-backend-staging-00012-rhp`, rollback candidate `coordit-backend-staging-00011-h7k` | retain the explicit naming variance in the change record; deploy only an immutable reviewed source |
| Supabase | Owner approved `coordit-staging`; the FREE project reports no managed backup. Direct failed on its IPv6 route, so the displayed Session pooler was used after `SESSION_POOLER_TCP_OK`. The resulting Cloud Shell dump is 2,085,267 bytes with recorded SHA-256 | download it to a secure owner-controlled local path and prove the checksum matches before migration |
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

The normal policy is to keep production targets distinct from staging. For this release, the owner explicitly approved the existing staging-named resources as production; that variance must remain in the change record. Two public hosts resolve successfully for the approved Cloud Run service:

- the Release project embeds `https://coordit-backend-staging-gei6wjuuiq-du.a.run.app`;
- Cloud Run and AdMob expose `https://coordit-backend-staging-789827940031.asia-northeast3.run.app`.

Fresh `curl --fail` checks returned HTTP 200 and `{"ok":true,"service":"coordit-backend"}` from both `/health` URLs. Use the Cloud Run console host for provider callbacks and retain the Release alias only while its health result and owner variance remain recorded.

## 3. Supabase production migration gate

1. Confirm the project in the dashboard and in the selected migration runner. Compare its project name/reference with the change record before every database command.
2. Create and record a recoverable backup or PITR checkpoint. Stop if recovery is unavailable or untested.
3. Dry-run the complete migration sequence against an empty disposable database and then a production-like staging copy.
4. Apply the version-controlled migrations through the owner-approved production pipeline, not by pasting ad hoc SQL into the production dashboard.
5. Capture the runner's full-filename ledger and schema verification output without row data or credentials.

Required ordered files are:

1. `20260511_add_styling_looks.sql`
2. `20260522_rename_inseam_to_outseam.sql`
3. `20260629_add_part_feedback_to_user_feedback.sql`
4. `20260707_add_consent_schema.sql`
5. `20260722_add_clothing_fit_assessments.sql`
6. `20260726_add_product_url_import.sql`
7. `20260730_add_atomic_closet_save.sql`
8. `20260730_add_thread_wallet.sql`
9. `20260806_add_fit_report_thread_charge.sql`
10. `20260809_add_apple_iap_thread_credit.sql`
11. `20260811_add_admob_rewarded_ssv.sql`
12. `20260813_add_user_birth_date.sql`
13. `20260814_harden_admob_reward_atomicity.sql`
14. `20260821_add_apple_iap_notification_receipts.sql`

The repository currently has no `supabase/config.toml`, and two files share the `20260730` prefix. Do not assume a vanilla `supabase db push` will create an unambiguous ledger. The owner-approved runner must preserve the listed full-file ordering and record every full filename. At minimum, the production evidence must prove the Apple ledger migration, AdMob base migration, AdMob hardening migration, and Apple notification migration are present.

After migration, verify without exposing user rows:

- `thread_balances` and `thread_ledger_entries` exist with RLS enabled;
- `apple_iap_transactions`, `admob_reward_attempts`, `admob_reward_transactions`, and `apple_iap_notification_receipts` exist with RLS enabled;
- service-role-only RPC permissions match the checked-in migrations;
- the migration ledger contains every filename above exactly once;
- Security Advisor, SSL enforcement, backups/PITR, network restrictions, and production Auth settings have owner-reviewed results.

Supabase's current production guidance recommends distinct environments, version-controlled migrations, RLS review, backups/PITR, and restricted production access: <https://supabase.com/docs/guides/deployment/going-into-prod>.

## 4. Cloud Run production service

Deploy only to the existing owner-approved `coordit-backend-staging` service in `coordit-dev`; its staging-style name is an explicit release variance, not permission to create or substitute another service. Build from the exact approved release-candidate commit and use an immutable image digest or commit-derived immutable tag; do not deploy `latest`. Start with both monetization flags false.

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
| Migration ledger | all 14 full filenames recorded exactly once; four monetary migrations verified | keep both flags false |
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
