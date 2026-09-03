# coordit Backend

Express + TypeScript REST API for the coordit MVP.

## Commands

```bash
npm install
npm run dev
npm run typecheck
```

## Key Endpoint

`POST /auth/guest` creates a Supabase anonymous session without requiring a
social login. `POST /auth/guest/welcome` verifies the iOS DeviceCheck token and
issues the one-time three-thread welcome grant. The second endpoint fails closed
when DeviceCheck is unavailable, so reinstalling cannot mint another grant.

Apple and Google login requests can include the current guest bearer token and
refresh token. A new social identity is linked to the anonymous Supabase user in
place. If that identity already belongs to a member, the backend atomically
merges the guest's closet, Fit Lab history, and remaining thread balance into
the existing account.

`POST /fit/recommend` performs one metered MVP recommendation with Supabase persistence.
It requires a UUID `idempotencyKey`; clients must reuse that key while retrying the same analysis.

`POST /clothing-items/with-size` atomically saves a closet item and its selected measurements.
It also requires a UUID `idempotencyKey` so a retry returns the first saved pair instead of creating duplicates.

`POST /fit-analysis-results/:id/report` builds a fit report from a saved fit result, calls OpenRouter with a strict JSON Schema, and falls back to a deterministic report if OpenRouter is unavailable or returns an invalid response.

`POST /api/v1/products/import-url/preview` analyzes one public product URL without saving it. Setup, API examples, persistence flow, Playwright deployment, and adapter guidance are documented in [`docs/PRODUCT_URL_IMPORT.md`](../docs/PRODUCT_URL_IMPORT.md).

## OpenRouter Fit Report Env

```bash
OPENROUTER_API_KEY=sk-or-v1-...
OPENROUTER_MODEL=google/gemini-2.5-flash
OPENROUTER_TIMEOUT_MS=20000
```

Fit-report calls use `response_format: json_schema` with strict validation,
require a compatible provider, and request zero data retention with data
collection disabled. The API key belongs only in the backend environment; never
in the iOS app or a committed file.

## Guest Auth Requirements

- Enable anonymous sign-ins and manual identity linking in Supabase Auth.
- Apply `supabase/migrations/20260902_add_guest_devicecheck_auth.sql`.
- Set `APPLE_DEVICECHECK_KEY_ID`, `APPLE_DEVICECHECK_TEAM_ID`, and
  `APPLE_DEVICECHECK_PRIVATE_KEY` only in the backend secret store.
- Use `APPLE_DEVICECHECK_ENVIRONMENT=production` for TestFlight/App Store builds.
