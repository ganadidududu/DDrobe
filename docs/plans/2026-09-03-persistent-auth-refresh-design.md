# Persistent Authentication Refresh Design

## Goal

Keep guest, Google, Apple, and email sessions signed in across normal app launches. Access-token expiry must be recovered automatically and must never erase the locally stored session. Only explicit logout or account deletion removes the session.

## Chosen approach

The backend exposes a public refresh-token exchange endpoint backed by a non-persistent Supabase auth client. The iOS app continues to own its session in Keychain, exchanges the saved refresh token at launch and before JWT expiry, saves rotated tokens atomically, and retries an authenticated operation once when the backend returns HTTP 401.

The app uses one in-flight refresh task so concurrent expired requests cannot rotate the same refresh token more than once. A request that failed with an older access token first reuses any newer session already published by another refresh.

Embedding the Supabase Swift SDK was rejected because the app already has a custom backend authentication boundary and adding a second session owner would create a broader migration. Extending access-token lifetime was rejected because it weakens credential security and still leaves eventual expiry unresolved.

## Failure behavior

- Network, server, and refresh failures retain the Keychain session and keep the returning-user flow active.
- A refreshed token pair replaces the prior pair in Keychain before it is published to callers.
- HTTP 401 triggers at most one refresh and one retry for an authenticated operation.
- Explicit logout and successful account deletion cancel scheduled refresh work and delete the Keychain record.
- Reinstallation may remove app-local state; no cross-install session recovery is promised.

## Client lifecycle

1. Load the saved session synchronously from Keychain so the returning user is not shown the login chooser.
2. On root-view startup, exchange the refresh token in the background.
3. Schedule another refresh shortly before the access token's JWT expiry.
4. Refresh again when the app becomes active if the token is close to expiry.
5. Give authenticated features a valid-token helper instead of reading the saved access token directly.

## Tests

- The refresh endpoint is public and validates its request.
- A valid Supabase refresh result returns the rotated token pair.
- Invalid refresh credentials return HTTP 401.
- Transient Supabase failures return a retryable server error.
- Existing backend typecheck and auth tests continue to pass.
- The iOS target builds with the persisted-session, scheduled-refresh, and 401-retry flow.
